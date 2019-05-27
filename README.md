# ngx_template_module

`ngx_template_module` is the module for generating nginx runtime configuration with templates and inventory YAML files.

This module may be comparable with jinja2 templating engine with limited functionality.

On starting nginx `ngx_template_module` 'on the fly' generate configuration.

# Build status
[![Build Status](https://travis-ci.org/ZigzagAK/ngx_template_module.svg)](https://travis-ci.org/ZigzagAK/ngx_template_module)

# Requirements

`ngx_template_module` requires [YAML](https://github.com/yaml/libyaml) library.

# Status

Beta version.

# Build

You may use `build.sh` script as a base. Simple run `build.sh build` and looking for a distributive in the `install` folder.

# Directives

## template

|Syntax |template|
|-------|----------------|
|Default|-|
|Syntax|template keyfile=inventory.yml [template=config.template]|
|Context|main,http,stream,server,location|

Reads the `inventory.yml` file and transforms `config.template` into valid nginx configuration fragment.  
`template` parameter may be absent. In this case `inventory.yml` file parsed and may be used in another templates.  

All changes of templates and inventories are checked in background. When configuration is changed, `ngx_template_module` send reload signal to master nginx process.  

# Quick Start

This example uses directives from [ngx_dynamic_healthcheck](https://github.com/ZigzagAK/ngx_dynamic_healthcheck) module.

## Nginx main config fragment

```nginx

template keyfile=env.yml template=env.template;

http {

    template keyfile=check.yml;
    template keyfile=servers.yml;

    template keyfile=backends.yml template=backend.template;
    template keyfile=entrypoints.yml template=entrypoint.template;

    server {
        listen 8888;

        location = /healthcheck/get {
            healthcheck_get;
        }

        location = /healthcheck/status {
            healthcheck_status;
        }
    }
}
```

## Templates

Env template
```nginx
env {{name}};
```

Upstream template
```nginx
upstream {{ name }} {
    zone shm_{{ name }} 256k;

{{ servers@{{name}}.servers }}

    check passive type=http rise={{ check.rise | default({{ check@http.rise }}) }} fall={{ check.fall | default({{ check@http.fall }}) }} timeout={{ check.timeout | default({{ check@http.timeout }})}} interval={{ check.interval | default({{ check@http.interval }}) }};
    check_request_uri {{ check.request.method | default({{ check@http.request.method }}) }} {{ check.request.uri | default({{ check@http.request.uri }}) }};
    check_response_codes {{ check.response.codes | default({{ check@http.response.codes }}) }};
    check_response_body {{ check.response.match | default({{ check@http.response.match }}) }};
}
```

Server template
```nginx
map 0 ${{name}} {
  {{map|default()}}
  default 0;
}

server {
    listen {{listen}} reuseport;

    default_type text/plain;

    location / {
        auth_request {{auth.request}};

        proxy_connect_timeout {{proxy.connect_timeout}};
        proxy_read_timeout {{proxy.read_timeout}};

        proxy_pass {{proxy.protocol}}://{{proxy.upstream|default({{name}})}};
    }

    location = /auth_stub {
        internal;
        return 200;
    }
}
```

## Inventories

```yaml
---
env:

  - name: LD_LIBRARY_PATH
```

```yaml
---
check:

  - name: http
    rise: 1
    fall: 2
    timeout: 10000
    interval: 10
    request:
      method: GET
      uri: /health
    response:
      codes: 200 204
      match: .*

  - name: tcp
    rise: 1
    fall: 2
    timeout: 10000
    interval: 10
```

Iterating over all objects in array and applying template for each object.  
All of parameters in YAML inventory MUST be a simple value or object (not an array). Arrays are unsupported except by in `servers` and `map` values.  
Parameters may be defined as a macros. Ex:  
```yaml
entrypoints:

  - name: app1
    param: global_group@name.param
    listen: "{{env(APP1_LISTEN_PORT)|default(33333)}}"
``` 
where `global_group` is a top level element in YAML file. You may access to all of loaded inventories with `group@name.xxx` syntax usage.
`template` directives must be declared in right order. This syntax may be used in templates and inventories.  

Three upstreams will be created with directive `template keyfile=backends.yml template=backend.template;`.
```yaml
---
backends:

  - name: app1
    server:
      max_conns: 10
      max_fails: 2
      fail_timeout: 30s
    check:
      rise: 1
      fall: 2
      timeout: 10000
      interval: 10
      request:
        method: GET
        uri: /health
      response:
        codes: 200 204
        match: .*

  - name: app2
    server:
      max_conns: 100
      max_fails: 2
      fail_timeout: 30s
    check:
      rise: 1
      fall: 2
      timeout: 10000
      interval: 10
      request:
        method: GET
        uri: /health
      response:
        codes: 200 204
        match: .*

  - name: app3
    server:
      max_conns: 100
      max_fails: 2
      fail_timeout: 30s
```

Three servers will be created with directive `template keyfile=entrypoints.yml template=enptrypoint.template;`.
```yaml
---
entrypoints:

  - name: app1
    listen: "{{env(APP1_LISTEN_PORT)|default(33333)}}"
    auth:
      request: /auth_stub
    proxy:
      connect_timeout: 10s
      read_timeout: 60s
      protocol: http
      upstream: app1

  - name: app2
    listen: "{{env(APP2_LISTEN_PORT)|default(44444)}}"
    auth:
      request: /auth_stub
    proxy:
      connect_timeout: 10s
      read_timeout: 60s
      protocol: http

  - name: app3
    listen: 8081
    auth:
      request: /auth_stub
    proxy:
      connect_timeout: 10s
      read_timeout: 60s
      protocol: http
    map:
      - a 1;
      - b 2;
      - c 3;
```

Separate YAML file for all upstream's servers.
```yaml
---
servers:

  - name: app1
    servers:
      - server 127.0.0.1:8001 max_conns={{backends@{{name}}.server.max_conns}};
      - server 127.0.0.1:8002 max_conns={{backends@{{name}}.server.max_conns}};

  - name: app2
    servers:
      - server 127.0.0.1:9001 max_conns={{backends@{{name}}.server.max_conns}};
      - server 127.0.0.1:9002 max_conns={{backends@{{name}}.server.max_conns}};

  - name: app3
    servers:
      - server 127.0.0.1:7001 max_conns={{backends@{{name}}.server.max_conns}};
      - server 127.0.0.1:7002 max_conns={{backends@{{name}}.server.max_conns}};
```

# License

See [LICENSE](https://github.com/ZigzagAK/ngx_template_module/blob/master/LICENSE).
