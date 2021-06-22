{
  async = {
    dependencies = ["console" "nio4r" "timers"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1lh36bsb41vllyrkiffs8qba2ilcjl7nrywizrb8ffrix50rfjn9";
      type = "gem";
    };
    version = "1.29.1";
  };
  async-http = {
    dependencies = ["async" "async-io" "async-pool" "protocol-http" "protocol-http1" "protocol-http2"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1a1si0iz1m6b1lzd5f8cvf1cbniy8kqc06n10bn74l1ppx8a6lc2";
      type = "gem";
    };
    version = "0.56.3";
  };
  async-io = {
    dependencies = ["async"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1z58cgnw79idasx63knyjqihxp5v4wrp7r4jf251a8kyykwdd83a";
      type = "gem";
    };
    version = "1.32.1";
  };
  async-pool = {
    dependencies = ["async"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1rq62gnhiy4a275wid465xqv6f6xsmp1zd9002xw4b37y83y5rqg";
      type = "gem";
    };
    version = "0.3.7";
  };
  console = {
    dependencies = ["fiber-local"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "04vhg3vnj2ky00fld4v6qywx32z4pjsa7l8i7sl1bl213s8334l9";
      type = "gem";
    };
    version = "1.13.1";
  };
  daemons = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1fki1aipqafqlg8xy25ykk0ql1dciy9kk6lcp5gzgkh9ccmaxzf3";
      type = "gem";
    };
    version = "1.4.0";
  };
  eventmachine = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0wh9aqb0skz80fhfn66lbpr4f86ya2z5rx6gm5xlfhd05bj1ch4r";
      type = "gem";
    };
    version = "1.2.7";
  };
  fiber-local = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1vrxxb09fc7aicb9zb0pmn5akggjy21dmxkdl3w949y4q05rldr9";
      type = "gem";
    };
    version = "1.0.0";
  };
  nio4r = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "00fwz0qq7agd2xkdz02i8li236qvwhma3p0jdn5bdvc21b7ydzd5";
      type = "gem";
    };
    version = "2.5.7";
  };
  pg = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "13mfrysrdrh8cka1d96zm0lnfs59i5x2g6ps49r2kz5p3q81xrzj";
      type = "gem";
    };
    version = "1.2.3";
  };
  protocol-hpack = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0sd85am1hj2w7z5hv19wy1nbisxfr1vqx3wlxjfz9xy7x7s6aczw";
      type = "gem";
    };
    version = "1.4.2";
  };
  protocol-http = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "10kk0jldnr5b5zlizbs23plkhjzi5yrb66qyplaki47nsc1fr2m5";
      type = "gem";
    };
    version = "0.22.2";
  };
  protocol-http1 = {
    dependencies = ["protocol-http"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0wp9pi1qjh1darrqv0r46i4bvax3n64aa0mn7kza4251qmk0dwz5";
      type = "gem";
    };
    version = "0.14.1";
  };
  protocol-http2 = {
    dependencies = ["protocol-hpack" "protocol-http"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1a9klpfmi7w465zq5xz8y8h1qvj42hkm0qd0nlws9d2idd767q5j";
      type = "gem";
    };
    version = "0.14.2";
  };
  rack = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0i5vs0dph9i5jn8dfc6aqd6njcafmb20rwqngrf759c9cvmyff16";
      type = "gem";
    };
    version = "2.2.3";
  };
  roda = {
    dependencies = ["rack"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0bnkd15x8vknhwn3g697qdgg05vdj91aq4m0s8iym359b2bagbmf";
      type = "gem";
    };
    version = "3.45.0";
  };
  sequel = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "04v2pz9dzwpl5zb3bblccms9lvz7600bia8a52f6h1sg5przvc8z";
      type = "gem";
    };
    version = "5.45.0";
  };
  thin = {
    dependencies = ["daemons" "eventmachine" "rack"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "123bh7qlv6shk8bg8cjc84ix8bhlfcilwnn3iy6zq3l57yaplm9l";
      type = "gem";
    };
    version = "1.8.1";
  };
  timers = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "00xdi97gm01alfqhjgvv5sff9n1n2l6aym69s9jh8l9clg63b0jc";
      type = "gem";
    };
    version = "4.3.3";
  };
}
