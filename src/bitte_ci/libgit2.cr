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

  enum Checkout
    None                  = 0
    Safe                  = 1 << 0
    Force                 = 1 << 1
    RecreateMissing       = 1 << 2
    AllowConflicts        = 1 << 4
    RemoveUntracked       = 1 << 5
    RemoveIgnored         = 1 << 6
    UpdateOnly            = 1 << 7
    DontUpdateIndex       = 1 << 8
    NoRefresh             = 1 << 9
    SkipUnmerged          = 1 << 10
    UseOurs               = 1 << 11
    UseTheirs             = 1 << 12
    DisablePathspecMatch  = 1 << 13
    SkipLockedDirectories = 1 << 18
    DontOverwriteIgnored  = 1 << 19
    ConflictStyleMerge    = 1 << 20
    ConflictStyleDiff3    = 1 << 21
    DontRemoveExisting    = 1 << 22
    DontWriteIndex        = 1 << 23
  end

  enum ObjectT
    Any      = -2
    Invalid  = -1
    Commit   =  1
    Tree     =  2
    Blob     =  3
    Tag      =  4
    OfsDelta =  6
    RefDelta =  7
  end

  enum GitCredential
    UserpassPlaintext = 1 << 0
    SshKey            = 1 << 1
    SshCustom         = 1 << 2
    Default           = 1 << 3
    SshInteractive    = 1 << 4
    Username          = 1 << 5
    SshMemory         = 1 << 6
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
  type Credential = Void*

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
    checkout_strategy : Checkout
    disable_filters : LibC::Int
    dir_mode : LibC::UInt
    file_mode : LibC::UInt
    file_open_flags : LibC::Int
    notify_flags : LibC::UInt
    git_checkout_notify_cb : Void*
    notify_payload : Void*
    progress_cb : Void*
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
    callbacks : RemoteCallbacks
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
    repository_cb : Void*
    repository_cb_payload : Void*
    remote_cb : Void*
    remote_cb_payload : Void*
  end

  struct RemoteCallbacks
    version : LibC::UInt
    sideband_progress : Void*
    completion : Void*
    credentials : Void*
    certificate_check : Void*
    transfer_progress : Void*
    update_tips : Void*
    pack_progress : Void*
    push_transfer_progress : Void*
    push_update_reference : Void*
    push_negotiation : Void*
    transport : Void*
    payload : Void*
    resolve_url : Void*
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
    None       = 0
    Nomemory
    Os
    Invalid
    Reference
    Zlib
    Repository
    Config
    Regex
    Odb
    Index
    Object
    Net
    Tag
    Tree
    Indexer
    Ssl
    Submodule
    Thread
    Stash
    Checkout
    Fetchhead
    Merge
    Ssh
    Filter
    Revert
    Callback
    Cherrypick
    Describe
    Rebase
    Filesystem
    Patch
    Worktree
    Sha1
    Http
    Internal
  end

  enum Reset
    Soft  = 1
    Mixed
    Hard
  end

  struct GitError
    message : LibC::Char*
    klass : LibC::Int
  end

  fun git_error_last : GitError*
  fun git_error_clear

  fun git_fetch_options_init(out : FetchOptions*, version : LibC::UInt) : LibC::Int

  fun git_remote_create(out : Remote*, repo : Repository, name : LibC::Char*, url : LibC::Char*) : LibC::Int
  fun git_remote_fetch(remote : Remote, refspecs : Strarray*, opts : FetchOptions*, reflog_message : LibC::Char*) : LibC::Int
  fun git_remote_list(out : Strarray*, repo : Repository) : LibC::Int
  fun git_remote_lookup(out : Remote*, repo : Repository, name : LibC::Char*) : LibC::Int
  fun git_remote_init_callbacks(out : RemoteCallbacks*, version : LibC::UInt) : LibC::Int

  fun git_checkout_options_init(out : CheckoutOptions*, version : LibC::UInt) : LibC::Int
  fun git_checkout_tree(repo : Repository, treeish : Object, opts : CheckoutOptions*) : LibC::Int

  fun git_clone_options_init(out : CloneOptions*, version : LibC::UInt) : LibC::Int
  fun git_clone(out : Repository*, url : LibC::Char*, local_path : LibC::Char*, git_clone_options : CloneOptions*) : LibC::Int

  fun git_refspec_parse(out : Refspec**, input : LibC::Char*, is_fetch : LibC::Int) : LibC::Int

  fun git_commit_lookup(out : Commit*, repo : Repository, oid : OID*) : LibC::Int

  fun git_libgit2_init : LibC::Int

  fun git_credential_userpass_plaintext_new(Credential**, username : LibC::Char*, password : LibC::Char*) : LibC::Int
  fun git_credential_userpass(Credential**, url : LibC::Char*, user_from_url : LibC::Char*, allowed_types : LibC::UInt, payload : Void*) : LibC::Int
  fun git_credential_ssh_key_new(Credential**, username : LibC::Char*, publickey : LibC::Char*, privatekey : LibC::Char*, passphrase : LibC::Char*) : LibC::Int
  fun git_credential_ssh_key_from_agent(Credential**, username : LibC::Char*) : LibC::Int

  fun git_object_lookup(out : Object*, repo : Repository, oid : OID*, type : ObjectT) : LibC::Int

  fun git_oid_fmt(str : UInt8*, oid : OID*) : LibC::Int
  fun git_oid_fromstrn(out : OID*, str : LibC::Char*, len : LibC::SizeT) : LibC::Int
  fun git_oid_fromstr(out : OID*, str : LibC::Char*) : LibC::Int
  fun git_oid_tostr_s(oid : OID*) : LibC::Char*

  fun git_repository_head(out : Reference*, repo : Repository) : LibC::Int
  fun git_repository_init(out : Repository*, path : LibC::Char*, is_bare : LibC::UInt) : LibC::Int
  fun git_repository_open(out : Repository*, path : LibC::Char*) : LibC::Int

  fun git_reset(repo : Repository, target : Object, reset_type : Reset, checkout_opts : CheckoutOptions*) : LibC::Int

  fun git_submodule_init(out : Submodule*, overwrite : LibC::Int) : LibC::Int
  fun git_submodule_foreach(
    repo : Repository,
    callback : Submodule*, LibC::Char*, Void* -> LibC::Int,
    payload : Void*
  ) : LibC::Int

  fun git_submodule_update(submodule : Submodule*, init : LibC::Int, options : SubmoduleUpdateOptions*) : LibC::Int
  fun git_submodule_update_options_init(out : SubmoduleUpdateOptions*, version : LibC::UInt) : LibC::Int
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
      check(LibGit.git_reset(@repo, obj, LibGit::Reset::Hard, pointerof(checkout_options)))
    end

    def object_lookup(rev)
      check(LibGit.git_oid_fromstr(out oid, rev))
      check(LibGit.git_object_lookup(out obj, @repo, pointerof(oid), LibGit::ObjectT::Any))
      obj
    end

    def remote_lookup(name)
      check(LibGit.git_remote_lookup(out remote, @repo, name))
      remote
    end

    def submodule_update_options_init : LibGit::SubmoduleUpdateOptions
      check(LibGit.git_submodule_update_options_init(out submodule_update_options, 1))
      submodule_update_options
    end

    def fetch_submodules(given_creds)
      submodule_update_options = submodule_update_options_init
      fetch_options = Git.fetch_options_init(given_creds)
      submodule_update_options.fetch_opts = fetch_options
      boxed_submodule_update_options = Box.box(submodule_update_options)
      LibGit.git_submodule_foreach(
        @repo,
        ->(submodule, name, payload) {
          v = Box(LibGit::SubmoduleUpdateOptions).unbox(payload)
          Helper.check(LibGit.git_submodule_update(submodule, 1, pointerof(v)))
          LibC::Int.new(0)
        },
        boxed_submodule_update_options
      )
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

  def self.clone_options_init : LibGit::CloneOptions
    check(LibGit.git_clone_options_init(out clone_options, 1))
    clone_options
  end

  def self.clone(url, path, given_creds : Credentials) : Repository
    clone_options = clone_options_init
    fetch_options = fetch_options_init(given_creds)
    clone_options.fetch_opts = fetch_options

    check(LibGit.git_clone(out repo, url, path, pointerof(clone_options)))

    Repository.new(repo)
  end

  def self.clone(url, path) : Repository
    check(LibGit.git_clone(out repo, url, path, nil))

    Repository.new(repo)
  end

  def self.checkout_options_init
    check(LibGit.git_checkout_options_init(out checkout_options, 1))
    checkout_options.checkout_strategy = LibGit::Checkout::Force
    checkout_options
  end

  def self.object_lookup(repo, sha1)
    check(LibGit.git_oid_fromstr(out oid, sha1))
    check(LibGit.git_object_lookup(out obj, repo, oid.pointer, LibGit::OBJECT::ANY))
    obj
  end

  def self.remote_create(repo, name, url)
    check(LibGit.git_remote_create(out remote, repo, name, url))
    remote
  end

  def self.remote_fetch(remote, refspecs, given_creds : Credentials)
    specs = LibGit::Strarray.new
    specs.strings = refspecs.map(&.to_unsafe).to_unsafe
    specs.count = refspecs.size
    fetch_options = fetch_options_init(given_creds)
    check(LibGit.git_remote_fetch(remote, pointerof(specs), pointerof(fetch_options), nil))
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

  struct Credentials
    property https_username : String?
    property https_password : String?
    property ssh_user : String?
    property ssh_public_path : String?
    property ssh_private_path : String?
    property ssh_passphrase : String

    def initialize(@https_username = nil, @https_password = nil, @ssh_user = nil, @ssh_public_path = nil, @ssh_private_path = nil, @ssh_passphrase = "")
    end

    def ssh_private_path
      @ssh_private_path || raise "Path to the SSH private key must be set"
    end

    def ssh_public_path
      @ssh_public_path || raise "Path to the SSH public key must be set"
    end
  end

  def self.credentials(
    credential : LibGit::Credential**,
    url : String,
    url_user : String?,
    allowed_types : LibGit::GitCredential,
    payload : Credentials
  )
    case
    when allowed_types & LibGit::GitCredential::SshKey == LibGit::GitCredential::SshKey
      user = payload.ssh_user || url_user || "git"

      res = LibGit.git_credential_ssh_key_from_agent(
        credential,
        user,
      )

      if res != 0
        check(LibGit.git_credential_ssh_key_new(
          credential,
          user,
          payload.ssh_public_path,
          payload.ssh_private_path,
          payload.ssh_passphrase,
        ))
      end
    when allowed_types & LibGit::GitCredential::UserpassPlaintext == LibGit::GitCredential::UserpassPlaintext
      https_username = payload.https_username || url_user
      raise "HTTPS username is missing" unless https_username

      https_password = payload.https_password
      raise "HTTPS password is missing" unless https_password

      check(LibGit.git_credential_userpass_plaintext_new(
        credential,
        https_username,
        https_password
      ))
    when allowed_types & LibGit::GitCredential::SshCustom == LibGit::GitCredential::SshCustom
      raise "Unsupported: LibGit::GitCredential::SshCustom"
    when allowed_types & LibGit::GitCredential::Default == LibGit::GitCredential::Default
      raise "Unsupported: LibGit::GitCredential::Default"
    when allowed_types & LibGit::GitCredential::SshInteractive == LibGit::GitCredential::SshInteractive
      raise "Unsupported: LibGit::GitCredential::SshInteractive"
    when allowed_types & LibGit::GitCredential::Username == LibGit::GitCredential::Username
      raise "Unsupported: LibGit::GitCredential::Username"
    when allowed_types & LibGit::GitCredential::SshMemory == LibGit::GitCredential::SshMemory
      raise "Unsupported: LibGit::GitCredential::SshMemory"
    end
  end

  def self.fetch_options_init(given_creds)
    check(LibGit.git_fetch_options_init(out fetch_options, 1))

    box = Box.box(given_creds)
    fetch_options.callbacks.payload = box

    fetch_options.callbacks.credentials = (->(credential : LibGit::Credential**, url : LibC::Char*, username_from_url : LibC::Char*, allowed_types : LibGit::GitCredential, payload : Void*) {
      url_username = String.new(username_from_url) if username_from_url
      v = Box(Credentials).unbox(payload)
      credentials(credential, String.new(url), url_username, allowed_types, v)
      0
    }).pointer

    fetch_options.callbacks.certificate_check = (->(cert : Void*, valid : LibC::Int, host : LibC::Char*, payload : Void*) {
      pp! String.new(host)
      0
    }).pointer

    fetch_options
  end
end
