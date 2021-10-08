package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"sync"
	"time"

	"github.com/hashicorp/nomad/api"
	"github.com/liftbridge-io/go-liftbridge"
	"github.com/pkg/errors"
	"github.com/uptrace/bun"
	"github.com/uptrace/bun/dialect/pgdialect"
	"github.com/uptrace/bun/driver/pgdriver"
	"github.com/uptrace/bun/extra/bundebug"
)

func brain() {
	client := connect()
	defer client.Close()

	message := map[string]interface{}{}
	lock := sync.Mutex{}

	ctx := context.Background()
	client.Subscribe(
		ctx,
		"brain-stream",
		func(msg *liftbridge.Message, err error) {
			fmt.Println(msg.Timestamp(), msg.Offset(), string(msg.Key()), string(msg.Value()))
			newMsg := map[string]interface{}{}
			unmarshalErr := json.Unmarshal(msg.Value(), &newMsg)
			if unmarshalErr != nil {
				fmt.Println("Invalid JSON received, ignoring: %w\n", unmarshalErr)
				return
			}

			lock.Lock()
			defer lock.Unlock()

			for k, v := range newMsg {
				message[k] = v
			}

			fmt.Printf("%#v\n", message)
		}, liftbridge.StartAtEarliestReceived(), liftbridge.Partition(0))

	for {
		time.Sleep(10 * time.Second)
	}

	fmt.Println("brain done")
	<-ctx.Done()
}

type Tree map[string]interface{}

func connect() liftbridge.Client {
	client, err := liftbridge.Connect([]string{"localhost:9292"})
	fail(errors.WithMessage(err, "Couldn't connect to NATS"))

	if err := client.CreateStream(
		context.Background(),
		"brain", "brain-stream",
		liftbridge.MaxReplication()); err != nil {
		if err != liftbridge.ErrStreamExists {
			fail(errors.WithMessage(err, "Failed to Create NATS Stream"))
		}
	} else {
		fmt.Println("Created stream brain-stream")
	}

	return client
}

func sub() {
	client := connect()
	defer client.Close()

	ctx := context.Background()
	err := client.Subscribe(
		ctx,
		"brain-stream",
		func(msg *liftbridge.Message, err error) {
			inputs := string(msg.Value())
			fmt.Println(msg.Timestamp(), msg.Offset(), string(msg.Key()), inputs)
			output, err := nixInstantiate(inputs)
			fmt.Println(string(output))
			fail(errors.WithMessage(err, "Failed to run nix-instantiate"))

			result := map[string]interface{}{}
			json.Unmarshal(output, &result)

			for key, value := range result {
				if _, ok := value.(string); ok {
					fmt.Printf("building %s\n", key)
					output, err = nixBuild(key, inputs)
					fmt.Println(string(output))
					fail(errors.WithMessage(err, "Failed to run nix-build"))
				}
			}
		}, liftbridge.StartAtEarliestReceived(), liftbridge.Partition(0))

	fail(errors.WithMessage(err, "failed to subscribe"))

	for {
		time.Sleep(10 * time.Second)
	}

	fmt.Println("subscription done")
	<-ctx.Done()
}

func nixBuild(name string, inputs string) ([]byte, error) {
	return exec.Command(
		"nix-build",
		"--no-out-link",
		"--expr",
		`{inputs, name}: (import ./foo3.nix { id = "foo1"; inputs = builtins.fromJSON inputs; }).${name}`,
		"--argstr", "inputs", inputs,
		"--argstr", "name", name,
	).CombinedOutput()
}

func nixInstantiate(inputs string) ([]byte, error) {
	return exec.Command(
		"nix-instantiate",
		"--eval",
		"--strict",
		"--json",
		"--expr",
		`{inputs}: import ./foo3.nix { id = "foo1"; inputs = builtins.fromJSON inputs; }`,
		"--argstr", "inputs", inputs,
	).CombinedOutput()
}

func pub() {
	client := connect()
	defer client.Close()

	fmt.Println("Start publishing")

	publish(client, map[string]interface{}{})

	fmt.Println("Done publishing")
}

func publish(client liftbridge.Client, msg map[string]interface{}) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	enc, err := json.Marshal(msg)
	fail(errors.WithMessage(err, "Failed to encode JSON"))

	_, err = client.Publish(ctx, "brain-stream",
		enc,
		liftbridge.Key([]byte("brain")),
		liftbridge.PartitionByKey(),
		liftbridge.AckPolicyAll(),
	)

	if err != nil {
		panic(err)
	}
}

func main() {
	go pub()
	go brain()
	sub()

	os.Exit(0)

	dsn := os.Getenv("POSTGRES_URL")
	sqldb := sql.OpenDB(pgdriver.NewConnector(pgdriver.WithDSN(dsn)))
	db := bun.NewDB(sqldb, pgdialect.New())
	db.AddQueryHook(bundebug.NewQueryHook(bundebug.WithVerbose()))

	config := api.Config{}
	client, err := api.NewClient(&config)
	if err != nil {
		panic(err)
	}

	nodes := client.Nodes()
	nodeList, _, err := nodes.List(nil)
	fail(errors.WithMessage(err, "while listing nodes"))

	for _, nodeStub := range nodeList {
		node, _, err := nodes.Info(nodeStub.ID, nil)
		fail(errors.WithMessage(err, "while fetching node"))
		fail(errors.WithMessage(handleNode(db, node), "while updating nodes"))
	}

	stream := client.EventStream()

	ctx := context.Background()
	topics := map[api.Topic][]string{
		api.TopicAllocation: {"*"},
		api.TopicDeployment: {"*"},
		api.TopicEvaluation: {"*"},
		api.TopicJob:        {"*"},
		api.TopicNode:       {"*"},
	}
	var index uint64
	err = db.NewSelect().Table("allocations").ColumnExpr(`COALESCE(MAX(index), 0)`).Scan(context.Background(), &index)
	fail(errors.WithMessage(err, "while fetching last known index"))

	events, err := stream.Stream(ctx, topics, index, nil)
	fail(errors.WithMessage(err, "While opening the nomad event stream"))

	for eventWrapper := range events {
		fail(errors.WithMessage(eventWrapper.Err, "While receiving events"))
		for _, event := range eventWrapper.Events {
			fmt.Printf("Event: %d: %s: %s: %s\n", event.Index, event.Topic, event.Type, event.Key)
			switch event.Topic {
			case api.TopicDeployment:
				fmt.Printf("%s\n", event.Type)
				deployment, err := event.Deployment()
				fail(errors.WithMessage(err, "while decoding Deployment payload"))
				handleDeployment(db, deployment)
			case api.TopicEvaluation:
				fmt.Printf("%s\n", event.Type)
				eval, err := event.Evaluation()
				fail(errors.WithMessage(err, "while decoding Evaluation payload"))
				handleEvaluation(db, eval)
			case api.TopicJob:
				fmt.Printf("%s\n", event.Type)
				job, err := event.Job()
				fail(errors.WithMessage(err, "while decoding Job payload"))
				handleJob(db, job)
			case api.TopicNode:
				fmt.Printf("%s\n", event.Type)
				node, err := event.Node()
				fail(errors.WithMessage(err, "while decoding Node payload"))
				handleNode(db, node)
			case api.TopicAllocation:
				alloc, err := event.Allocation()
				fail(errors.WithMessage(err, "while decoding Allocation payload"))
				handleAllocation(db, alloc, event.Index)
			}
		}
	}
}

type Deployment struct {
	ID        string
	Data      *api.Deployment
	CreatedAt time.Time `bun:",nullzero,notnull,default:current_timestamp"`
	UpdatedAt time.Time `bun:",nullzero,notnull,default:current_timestamp"`
}

func handleDeployment(db *bun.DB, deployment *api.Deployment) {
	mdeployment := Deployment{
		ID:   deployment.ID,
		Data: deployment,
	}

	_, err := db.NewInsert().
		Model(&mdeployment).
		On("CONFLICT (id) DO UPDATE").
		Exec(context.Background())
	fail(errors.WithMessage(err, "while inserting an deployment"))
}

type Evaluation struct {
	ID        string
	JobID     string
	Status    string
	CreatedAt time.Time `bun:",nullzero,notnull,default:current_timestamp"`
	UpdatedAt time.Time `bun:",nullzero,notnull,default:current_timestamp"`
}

func handleEvaluation(db *bun.DB, eval *api.Evaluation) {
	meval := Evaluation{
		ID:        eval.ID,
		JobID:     eval.JobID,
		Status:    eval.Status,
		CreatedAt: nanos(eval.CreateTime),
		UpdatedAt: nanos(eval.ModifyTime),
	}

	_, err := db.NewInsert().
		Model(&meval).
		On("CONFLICT (id) DO UPDATE").
		Exec(context.Background())
	fail(errors.WithMessage(err, "while inserting an evaluation"))
}

type Job struct {
	ID        string
	Data      *api.Job
	CreatedAt time.Time `bun:",nullzero,notnull,default:current_timestamp"`
	UpdatedAt time.Time `bun:",nullzero,notnull,default:current_timestamp"`
}

func handleJob(db *bun.DB, job *api.Job) {
	mjob := Job{
		ID:   *job.ID,
		Data: job,
	}

	_, err := db.NewInsert().
		Model(&mjob).
		On("CONFLICT (id) DO UPDATE").
		Exec(context.Background())
	fail(errors.WithMessage(err, "while inserting a job"))
}

type Allocation struct {
	ID           string
	EvalID       string
	JobID        string
	Index        uint64
	ClientStatus string
	Data         *api.Allocation
	CreatedAt    time.Time `bun:",nullzero,notnull,default:current_timestamp"`
	UpdatedAt    time.Time `bun:",nullzero,notnull,default:current_timestamp"`
}

func nanos(n int64) time.Time {
	return time.Unix(0, 0).Add(time.Duration(n) * time.Nanosecond)
}

func handleAllocation(db *bun.DB, alloc *api.Allocation, index uint64) {
	malloc := Allocation{
		ID:           alloc.ID,
		EvalID:       alloc.EvalID,
		JobID:        alloc.JobID,
		Index:        index,
		ClientStatus: alloc.ClientStatus,
		Data:         alloc,
		CreatedAt:    nanos(alloc.CreateTime),
		UpdatedAt:    nanos(alloc.ModifyTime),
	}

	_, err := db.NewInsert().
		Model(&malloc).
		On("CONFLICT (id) DO UPDATE").
		Exec(context.Background())

	fail(errors.WithMessage(err, "while inserting an allocation"))
}

type Node struct {
	ID        string
	Data      *api.Node
	CreatedAt time.Time
	UpdatedAt time.Time
}

func handleNode(db *bun.DB, nodeStub *api.Node) error {
	node := Node{
		ID:        nodeStub.ID,
		Data:      nodeStub,
		UpdatedAt: time.Now().UTC(),
	}

	_, err := db.NewInsert().
		Model(&node).
		On("CONFLICT (id) DO UPDATE").
		Exec(context.Background())

	return errors.Wrap(err, "during initial node update")
}

func fail(err error) {
	if err != nil {
		panic(err)
	}
}
