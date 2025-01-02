local cjson = require "cjson.safe"
local xmlua = require "xmlua"

local ODataValidationHandler = {
    PRIORITY = 1010, -- set the plugin priority, which determines plugin execution order
    VERSION = "0.1",
}

function ODataValidationHandler:access(conf)
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

  -- Log the full OData specification for debugging
  kong.log.debug("OData specification content: ", odata_specification)

  -- Implement the actual validation logic against the OData specification
  local is_valid, validation_error = self:validate_odata_request(request_body, odata_specification)

  if not is_valid then
    kong.log.err("Validation failed: ", validation_error)
    return kong.response.exit(400, { message = validation_error or "Request does not conform to OData specification" })
  end
end

-- Function to validate the request against the OData specification
function ODataValidationHandler:validate_odata_request(request_body, odata_specification)
  -- Parse the OData specification
  local spec, err = self:parse_odata_specification(odata_specification)
  if err or not spec or #spec == 0 then
    kong.log.err("Failed to parse OData specification: ", err or "Specification is empty")
    return false, "Invalid OData specification"
  end

  -- Validate the request body against the parsed specification
  for _, entityType in ipairs(spec) do
    kong.log.debug("Validating entity type: ", entityType.Name)
    for _, property in ipairs(entityType.Properties) do
      kong.log.debug("Checking property: ", property.Name)
      local value = request_body[property.Name]
      if property.Required and value == nil then
        kong.log.err("Missing required field: ", property.Name)
        return false, "Missing required field: " .. property.Name
      end
      if value ~= nil and type(value) ~= self:map_odata_type_to_lua(property.Type, entityType.Namespace) then
        kong.log.err("Field type mismatch for ", property.Name, ": expected ", property.Type, ", got ", type(value))
        return false, "Field " .. property.Name .. " must be of type " .. property.Type
      end
    end
  end

  return true
end

-- Function to map OData types to Lua types
function ODataValidationHandler:map_odata_type_to_lua(odata_type, namespace)
  -- Basic EDM type mappings
  local basic_type_mapping = {
    ["Edm.Int32"] = "number",
    ["Edm.String"] = "string",
    ["Edm.Decimal"] = "number",
    ["Edm.Boolean"] = "boolean",
    ["Edm.Date"] = "string",
    ["Edm.DateTimeOffset"] = "string"
  }

  -- Check if it's a collection type
  if odata_type:match("^Collection%(.*%)$") then
    return "table"
  end

  -- Check if it's a basic EDM type
  if basic_type_mapping[odata_type] then
    return basic_type_mapping[odata_type]
  end

  -- If it starts with the namespace, it's a complex type
  if namespace and odata_type:match("^" .. namespace .. "%.") then
    return "table"
  end

  -- Default to string for unknown types
  return "string"
end

-- Function to parse the OData specification
function ODataValidationHandler:parse_odata_specification(odata_specification)
  kong.log.debug("Parsing OData specification...")
  local document, parse_err = xmlua.XML.parse(odata_specification)
  if parse_err then
    kong.log.err("XML parsing error: ", parse_err)
    return nil, "XML parsing error"
  end

  local spec = {}
  local root = document:root()
  kong.log.debug("Root element name: ", root:name())

  local namespaces = {
    ["edmx"] = "http://docs.oasis-open.org/odata/ns/edmx"
  }

  -- Find Schema and get namespace
  local schemas = document:search("//*[local-name()='Schema']")
  if not schemas or #schemas == 0 then
    kong.log.err("No schemas found in the OData specification")
    return nil, "No schemas found"
  end

  -- Process each schema
  for _, schema in ipairs(schemas) do
    local namespace = schema:get_attribute("Namespace")
    kong.log.debug("Processing schema with namespace: ", namespace)

    -- First process ComplexTypes
    local complexTypes = schema:search("*[local-name()='ComplexType']")
    for _, complexType in ipairs(complexTypes) do
      local typeName = complexType:get_attribute("Name")
      local entity = {
        Name = typeName,
        Properties = {},
        IsComplexType = true
      }

      local properties = complexType:search("*[local-name()='Property']")
      for _, property in ipairs(properties) do
        local propName = property:get_attribute("Name")
        local propType = property:get_attribute("Type")
        local nullable = property:get_attribute("Nullable")
        
        table.insert(entity.Properties, {
          Name = propName,
          Type = propType,
          Required = nullable == "false"
        })
      end
      table.insert(spec, entity)
    end

    -- Then process EntityTypes
    local entityTypes = schema:search("*[local-name()='EntityType']")
    for _, entityType in ipairs(entityTypes) do
      local entityName = entityType:get_attribute("Name")
      local entity = {
        Name = entityName,
        Properties = {},
        Namespace = namespace
      }

      local properties = entityType:search("*[local-name()='Property']")
      for _, property in ipairs(properties) do
        local propName = property:get_attribute("Name")
        local propType = property:get_attribute("Type")
        local nullable = property:get_attribute("Nullable")
        
        table.insert(entity.Properties, {
          Name = propName,
          Type = propType,
          Required = nullable == "false"
        })
      end

      -- Also process NavigationProperties
      local navProperties = entityType:search("*[local-name()='NavigationProperty']")
      for _, navProperty in ipairs(navProperties) do
        local propName = navProperty:get_attribute("Name")
        local propType = navProperty:get_attribute("Type")
        
        table.insert(entity.Properties, {
          Name = propName,
          Type = propType,
          Required = false,
          IsNavigation = true
        })
      end

      table.insert(spec, entity)
    end
  end

  if #spec == 0 then
    kong.log.err("Parsed specification is empty")
  end

  return spec
end

return ODataValidationHandler 