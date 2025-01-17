# Create an init.d unit
Create file `/etc/init.d/inet_check` with content:
```
#!/bin/sh /etc/rc.common
USE_PROCD=1
START=95
STOP=01
start_service() {
    procd_open_instance
    procd_set_param command /usr/bin/inet_check.sh
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}
```

create `/usr/bin/inet_check.sh` with content from `down interface.sh` or `change rule.sh` file

make both of them it executable
```
chmod 755 /usr/bin/inet_check.sh /etc/init.d/inet_check
```

Enable the service `inet_check` in the openwrt GUI.
