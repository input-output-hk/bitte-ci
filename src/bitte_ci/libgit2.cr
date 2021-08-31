require "file_utils"

@[Link("ssh2")]
@[Link("git2")]
lib LibGit
  enum Fetch
    PruneUnspecified
    Prune
    NoPrune
  end

  enum RemoteDownloadTags
    Unspecified
    Auto
    None
    All
  end

  enum Proxy
    None
    Auto
    Specified
  end

  enum CloneLocal
    Auto
    Local
    NoLocal
    LocalNoLinks
  end

  enum CheckoutNotify
    None
    Conflict  = 1 << 0
    Dirty     = 1 << 1
    Updated   = 1 << 2
    Untracked = 1 << 3
    Ignored   = 1 << 4
    All       = 0x0FFFF
  end

  enum CHECKOUT
    NONE                    = 0
    SAFE                    = 1 << 0
    FORCE                   = 1 << 1
    RECREATE_MISSING        = 1 << 2
    ALLOW_CONFLICTS         = 1 << 4
    REMOVE_UNTRACKED        = 1 << 5
    REMOVE_IGNORED          = 1 << 6
    UPDATE_ONLY             = 1 << 7
    DONT_UPDATE_INDEX       = 1 << 8
    NO_REFRESH              = 1 << 9
    SKIP_UNMERGED           = 1 << 10
    USE_OURS                = 1 << 11
    USE_THEIRS              = 1 << 12
    DISABLE_PATHSPEC_MATCH  = 1 << 13
    SKIP_LOCKED_DIRECTORIES = 1 << 18
    DONT_OVERWRITE_IGNORED  = 1 << 19
    CONFLICT_STYLE_MERGE    = 1 << 20
    CONFLICT_STYLE_DIFF3    = 1 << 21
    DONT_REMOVE_EXISTING    = 1 << 22
    DONT_WRITE_INDEX        = 1 << 23
  end

  enum OBJECT
    ANY       = -2
    INVALID   = -1
    COMMIT    =  1
    TREE      =  2
    BLOB      =  3
    TAG       =  4
    OFS_DELTA =  6
    REF_DELTA =  7
  end

  alias UInt16T = LibC::UShort
  alias UInt32T = LibC::UInt
  type Diff = Void*
  type ObjectSize = UInt64
  type Remote = Void*
  type Repository = Void*
  type Object = Void*
  type Reference = Void*
  type Submodule = Void*
  type Payload = Void*

  struct Refspec
    string : LibC::Char*
    src : LibC::Char*
    dst : LibC::Char*
    force : LibC::UInt
  end

  struct DiffFile
    id : OID
    path : LibC::Char*
    size : ObjectSize
    flags : UInt32T
    mode : UInt32T
    id_abbrev : UInt16T
  end

  type CheckoutNotifyCb = CheckoutNotify, LibC::Char*, DiffFile, DiffFile, DiffFile, Void* -> LibC::Int
  type DiffProgressCb = Diff*, LibC::Char*, LibC::Char*, Void* -> LibC::Int
  type RepositoryCreateCb = Repository**, LibC::Char*, LibC::Int, Void* -> LibC::Int
  type RemoteCreateCb = Remote**, Repository*, LibC::Char*, LibC::Char*, Void* -> LibC::Int
  type SubmoduleCb = Submodule*, LibC::Char*, Payload* -> LibC::Int

  type Tree = Void*
  type Index = Void*

  struct OID
    id : UInt8[20]
  end

  struct Strarray
    strings : LibC::Char**
    count : LibC::SizeT
  end

  struct CheckoutOptions
    version : LibC::UInt
    checkout_strategy : CHECKOUT
    disable_filters : LibC::Int
    dir_mode : LibC::UInt
    file_mode : LibC::UInt
    file_open_flags : LibC::Int
    notify_flags : LibC::UInt
    git_checkout_notify_cb : CheckoutNotifyCb
    notify_payload : Void*
    progress_cb : DiffProgressCb
    progress_payload : Void*
    paths : Strarray
    baseline : Tree*
    baseline_index : Index*
    target_directory : LibC::Char*
    ancestor_label : LibC::Char*
    our_label : LibC::Char*
    their_label : LibC::Char*
    perfdata_cb : Void*
    perfdata_payload : Void*
  end

  struct ProxyOptions
    version : LibC::UInt
    type : Proxy
    url : LibC::Char*
    credentials : Void*
    certificate_check : Void*
    payload : Void*
  end

  struct FetchOptions
    version : LibC::Int
    callbacks : Void*
    prune : Fetch
    update_fetchhead : LibC::Int
    download_tags : RemoteDownloadTags
    proxy_opts : ProxyOptions
    custom_headers : Strarray
  end

  struct CloneOptions
    version : LibC::UInt
    checkout_opts : CheckoutOptions
    fetch_opts : FetchOptions
    bare : LibC::Int
    local : CloneLocal
    checkout_branch : LibC::Char*
    repository_cb : RepositoryCreateCb
    repository_cb_payload : Void*
    remote_cb : RemoteCreateCb
    remote_cb_payload : Void*
  end

  struct SubmoduleUpdateOptions
    version : LibC::UInt
    checkout_opts : CheckoutOptions
    fetch_opts : FetchOptions
    allow_fetch : LibC::Int
  end

  struct ArrayT
    ptr : Void*
    size : LibC::SizeT
    asize : LibC::SizeT
  end

  struct Time
    time : LibC::Int64T
    offset : LibC::Int
    sign : LibC::Char
  end

  struct Signature
    name : LibC::Char*
    email : LibC::Char*
    when : Time
  end

  struct Commit
    object : Object
    parent_ids : ArrayT
    tree_id : OID
    author : Signature*
    committer : Signature*
    message_encoding : LibC::Char*
    raw_message : LibC::Char*
    raw_header : LibC::Char*
    summary : LibC::Char*
    body : LibC::Char*
  end

  enum Error
    NONE       = 0
    NOMEMORY
    OS
    INVALID
    REFERENCE
    ZLIB
    REPOSITORY
    CONFIG
    REGEX
    ODB
    INDEX
    OBJECT
    NET
    TAG
    TREE
    INDEXER
    SSL
    SUBMODULE
    THREAD
    STASH
    CHECKOUT
    FETCHHEAD
    MERGE
    SSH
    FILTER
    REVERT
    CALLBACK
    CHERRYPICK
    DESCRIBE
    REBASE
    FILESYSTEM
    PATCH
    WORKTREE
    SHA1
    HTTP
    INTERNAL
  end

  enum RESET
    SOFT  = 1
    MIXED
    HARD
  end

  struct GitError
    message : LibC::Char*
    klass : LibC::Int
  end

  fun git_error_last : GitError*
  fun git_error_clear

  fun git_remote_create(out : Remote*, repo : Repository, name : LibC::Char*, url : LibC::Char*) : LibC::Int
  fun git_remote_fetch(remote : Remote, refspecs : Strarray*, opts : FetchOptions*, reflog_message : LibC::Char*) : LibC::Int
  fun git_remote_list(out : Strarray*, repo : Repository) : LibC::Int
  fun git_remote_lookup(out : Remote*, repo : Repository, name : LibC::Char*) : LibC::Int

  fun git_checkout_options_init(out : CheckoutOptions*, version : LibC::UInt) : LibC::Int
  fun git_checkout_tree(repo : Repository, treeish : Object, opts : CheckoutOptions*) : LibC::Int

  fun git_clone_options_init(out : CloneOptions*, version : LibC::UInt) : LibC::Int
  fun git_clone(out : Repository*, url : LibC::Char*, local_path : LibC::Char*, git_clone_options : CloneOptions*) : LibC::Int

  fun git_refspec_parse(out : Refspec**, input : LibC::Char*, is_fetch : LibC::Int) : LibC::Int

  fun git_commit_lookup(out : Commit*, repo : Repository, oid : OID*) : LibC::Int

  fun git_libgit2_init : LibC::Int

  fun git_object_lookup(out : Object*, repo : Repository, oid : OID*, type : OBJECT) : LibC::Int

  fun git_oid_fmt(str : UInt8*, oid : OID*) : LibC::Int
  fun git_oid_fromstrn(out : OID*, str : LibC::Char*, len : LibC::SizeT) : LibC::Int
  fun git_oid_fromstr(out : OID*, str : LibC::Char*) : LibC::Int
  fun git_oid_tostr_s(oid : OID*) : LibC::Char*

  fun git_repository_head(out : Reference*, repo : Repository) : LibC::Int
  fun git_repository_init(out : Repository*, path : LibC::Char*, is_bare : LibC::UInt) : LibC::Int
  fun git_repository_open(out : Repository*, path : LibC::Char*) : LibC::Int

  fun git_reset(repo : Repository, target : Object, reset_type : RESET, checkout_opts : CheckoutOptions*) : LibC::Int

  fun git_submodule_init(out : Submodule*, overwrite : LibC::Int) : LibC::Int
  fun git_submodule_foreach(
    repo : Repository,
    callback : Submodule*, LibC::Char*, Payload* -> LibC::Int,
    payload : Payload
  ) : LibC::Int

  fun git_submodule_update(submodule : Submodule*, init : LibC::Int, options : SubmoduleUpdateOptions*) : LibC::Int
end

module Git
  module Helper
    def self.check(res)
      return if res == 0
      e = LibGit.git_error_last
      if e.null?
        raise "LibGit error without message: #{res.inspect} (#{LibGit::Error.new(res)}"
      else
        raise "LibGit error: #{String.new(e.value.message)}"
      end
    end

    def check(res)
      Helper.check(res)
    end
  end

  extend Helper

  def self.init
    LibGit.git_libgit2_init
  end

  class Repository
    include Helper
    extend Helper

    @repo : LibGit::Repository

    def initialize(path, bare)
      @repo = check(LibGit.git_repository_init(out repo, path, bare ? 1 : 0))
    end

    def initialize(repo)
      @repo = repo
    end

    def self.init(path, bare) : self
      check(LibGit.git_repository_init(out repo, path, bare ? 1 : 0))
      new(repo)
    end

    def self.open(path) : self
      check(LibGit.git_repository_open(out repo, path))
      new(repo)
    end

    def reset(rev)
      obj = object_lookup(rev)
      checkout_options = Git.checkout_options_init
      check(LibGit.git_reset(@repo, obj, LibGit::RESET::HARD, pointerof(checkout_options)))
    end

    def object_lookup(rev)
      check(LibGit.git_oid_fromstr(out oid, rev))
      check(LibGit.git_object_lookup(out obj, @repo, pointerof(oid), LibGit::OBJECT::ANY))
      obj
    end

    def remote_lookup(name)
      check(LibGit.git_remote_lookup(out remote, @repo, name))
      remote
    end

    def fetch_submodules
      LibGit.git_submodule_foreach(
        @repo,
        ->(submodule, name, payload) {
          Helper.check(LibGit.git_submodule_update(submodule, 1, nil))
          LibC::Int.new(0)
        },
        nil
      )
    end
  end

  def self.clone(url, path) : Repository
    check(LibGit.git_clone(out repo, url, path, nil))
    Repository.new(repo)
  end

  def self.checkout(repo, sha1)
    checkout_options = checkout_options_init
    check(LibGit.git_checkout_tree(repo, obj, pointerof(checkout_options)))
  end

  def self.checkout_options_init
    check(LibGit.git_checkout_options_init(out checkout_options, 1))
    checkout_options.checkout_strategy = LibGit::CHECKOUT::FORCE
    checkout_options
  end

  def self.object_lookup(repo, sha1)
    check(LibGit.git_oid_fromstr(out oid, sha1))
    check(LibGit.git_object_lookup(out obj, repo, pointerof(oid), LibGit::OBJECT::ANY))
    obj
  end

  def self.remote_create(repo, name, url)
    check(LibGit.git_remote_create(out remote, repo, name, url))
    remote
  end

  def self.remote_fetch(remote, refspecs)
    specs = LibGit::Strarray.new
    specs.strings = refspecs.map(&.to_unsafe).to_unsafe
    specs.count = refspecs.size
    check(LibGit.git_remote_fetch(remote, pointerof(specs), nil, nil))
  end

  def self.remote_list(repo)
    check(LibGit.git_remote_list(out list, repo))
    list
  end

  def self.remote_lookup(repo, name)
    check(LibGit.git_remote_lookup(out remote, repo, name))
    remote
  end

  def self.refspec_parse(input, fetch)
    check(LibGit.git_refspec_parse(out refspec, input, fetch ? 1 : 0))
    refspec
  end
end
