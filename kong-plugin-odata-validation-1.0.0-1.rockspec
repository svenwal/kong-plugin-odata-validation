package = "kong-plugin-odata-validation"
version = "1.0.0-1"
source = {
  url = "git://your-repo-url.git",
}
description = {
  summary = "A Kong plugin for OData request validation",
  homepage = "https://your-plugin-homepage",
  license = "Apache-2.0"
}
dependencies = {
  "lua >= 5.1",
  "kong >= 2.0.0"
}
build = {
  type = "builtin",
  modules = {
    ["kong.plugins.odata-validation.handler"] = "kong/plugins/odata-validation/handler.lua",
    ["kong.plugins.odata-validation.schema"] = "kong/plugins/odata-validation/schema.lua",
  }
} 