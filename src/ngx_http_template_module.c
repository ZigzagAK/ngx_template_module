/*
 * Copyright (C) Aleksey Konovkin (alkon2000@mail.ru).
 */


#include <ngx_http.h>


#include "api/ngx_template.h"


static ngx_http_module_t ngx_http_template_ctx = {
    NULL,                              /* preconfiguration */
    NULL,                              /* postconfiguration */
    NULL,                              /* create main configuration */
    NULL,                              /* init main configuration */
    NULL,                              /* create server configuration */
    NULL,                              /* merge server configuration */
    NULL,                              /* create location configuration */
    NULL                               /* merge location configuration */
};


#define NGX_ALL_CONF (NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_UPS_CONF)


static ngx_command_t ngx_http_template_commands[] = {

    { ngx_string("template"),
      NGX_ALL_CONF|NGX_CONF_1MORE,
      ngx_template_directive,
      0,
      0,
      NULL },

    ngx_null_command

};


ngx_module_t ngx_http_template_module = {
    NGX_MODULE_V1,
    &ngx_http_template_ctx ,           /* module context */
    ngx_http_template_commands,        /* module directives */
    NGX_HTTP_MODULE,                   /* module type */
    NULL,                              /* init master */
    NULL,                              /* init module */
    NULL,                              /* init process */
    NULL,                              /* init thread */
    NULL,                              /* exit thread */
    NULL,                              /* exit process */
    NULL,                              /* exit master */
    NGX_MODULE_V1_PADDING
};
