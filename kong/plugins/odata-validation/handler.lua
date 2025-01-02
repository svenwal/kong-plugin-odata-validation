local BasePlugin = require "kong.plugins.base_plugin"
local cjson = require "cjson.safe"
local xmlua = require "xmlua"

local ODataValidationHandler = {
    PRIORITY = 1010, -- set the plugin priority, which determines plugin execution order
    VERSION = "0.1",
  }


function ODataValidationHandler:access(conf)
  ODataValidationHandler.super.access(self)

  -- Capture request metadata and body
  local request_method = kong.request.get_method()
  local request_path = kong.request.get_path()
  local request_body, err = kong.request.get_body()

  if err then
    return kong.response.exit(400, { message = "Invalid request body" })
  end

  -- Log the request details (for debugging purposes)
  kong.log.debug("Request method: ", request_method)
  kong.log.debug("Request path: ", request_path)
  kong.log.debug("Request body: ", cjson.encode(request_body))

  -- Validate against OData specification
  local odata_specification = conf.odata_specification
  if not odata_specification or odata_specification == "" then
    return kong.response.exit(500, { message = "OData specification not configured" })
  end

  if not request_path:match("/odata/") then
    return kong.response.exit(400, { message = "Invalid OData request path" })
  end

  -- Implement the actual validation logic against the OData specification
  local is_valid, validation_error = self:validate_odata_request(request_body, odata_specification)

  if not is_valid then
    return kong.response.exit(400, { message = validation_error or "Request does not conform to OData specification" })
  end
end

-- Function to validate the request against the OData specification
function ODataValidationHandler:validate_odata_request(request_body, odata_specification)
  -- Parse the OData specification
  local spec, err = self:parse_odata_specification(odata_specification)
  if err then
    kong.log.err("Failed to parse OData specification: ", err)
    return false, "Invalid OData specification"
  end

  -- Validate the request body against the parsed specification
  for _, entityType in ipairs(spec) do
    for _, property in ipairs(entityType.Properties) do
      local value = request_body[property.Name]
      if property.Required and value == nil then
        return false, "Missing required field: " .. property.Name
      end
      if value ~= nil and type(value) ~= property.Type then
        return false, "Field " .. property.Name .. " must be of type " .. property.Type
      end
      -- Add more validation rules based on the property constraints
    end
  end

  return true
end

-- Function to parse the OData specification
function ODataValidationHandler:parse_odata_specification(odata_specification)
  local document = xmlua.XML.parse(odata_specification)
  local spec = {}
  local schemas = document:search("edmx:Edmx/edmx:DataServices/Schema")

  for _, schema in ipairs(schemas) do
    local entityTypes = schema:search("EntityType")
    for _, entityType in ipairs(entityTypes) do
      local entity = {
        Name = entityType:attribute("Name"),
        Properties = {}
      }
      local properties = entityType:search("Property")
      for _, property in ipairs(properties) do
        table.insert(entity.Properties, {
          Name = property:attribute("Name"),
          Type = property:attribute("Type"),
          Required = property:attribute("Nullable") == "false"
        })
      end
      table.insert(spec, entity)
    end
  end

  return spec
end

return ODataValidationHandler 