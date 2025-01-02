package = "kong-plugin-odata-validation"
version = "1.1.0-1"
source = {
  url = "git@github.com:svenwal/kong-plugin-odata-validation.git",
}
description = {
  summary = "A Kong plugin for OData request validation",
  homepage = "https://github.com/svenwal/kong-plugin-odata-validation",
  license = "Apache-2.0"
}
dependencies = {
  "lua >= 5.1",
  "kong >= 3.8.0"
}
build = {
  type = "builtin",
  modules = {
    ["kong.plugins.odata-validation.handler"] = "kong/plugins/odata-validation/handler.lua",
    ["kong.plugins.odata-validation.schema"] = "kong/plugins/odata-validation/schema.lua",
  }
} 