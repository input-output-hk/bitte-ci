log_level = "TRACE"

client {
  chroot_env {
    "/etc/passwd" = "/etc/passwd"
    "./resolv.conf" = "/etc/resolv.conf" 
  }
}
