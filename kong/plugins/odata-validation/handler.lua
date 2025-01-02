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
      if value ~= nil and type(value) ~= self:map_odata_type_to_lua(property.Type) then
        kong.log.err("Field type mismatch for ", property.Name, ": expected ", property.Type, ", got ", type(value))
        return false, "Field " .. property.Name .. " must be of type " .. property.Type
      end
    end
  end

  return true
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
  
  -- First try to find the root element to verify the document loaded
  local root = document:root()
  kong.log.debug("Root element name: ", root:name())

  -- Define the namespaces used in the document
  local namespaces = {
    ["edmx"] = "http://docs.oasis-open.org/odata/ns/edmx"
  }

  -- First find the root Edmx element
  local edmx = document:search("//*[local-name()='Edmx']")[1]
  if not edmx then
    kong.log.err("No Edmx element found")
    return nil, "No Edmx element found"
  end
  kong.log.debug("Found Edmx element with name: ", edmx:name())

  -- Then find DataServices
  local dataServices = edmx:search("*[local-name()='DataServices']")[1]
  if not dataServices then
    kong.log.err("No DataServices found in the OData specification")
    return nil, "No DataServices found"
  end
  kong.log.debug("Found DataServices element with name: ", dataServices:name())

  -- Then find Schema
  local schemas = dataServices:search("*[local-name()='Schema']")
  if not schemas or #schemas == 0 then
    kong.log.err("No schemas found in the OData specification")
    return nil, "No schemas found"
  end
  kong.log.debug("Found schemas, count: ", #schemas)

  for _, schema in ipairs(schemas) do
    -- Safe attribute access
    local namespace = schema:get_attribute("Namespace")
    kong.log.debug("Processing schema with namespace: ", namespace)
    
    local entityTypes = schema:search("*[local-name()='EntityType']")
    if not entityTypes or #entityTypes == 0 then
      kong.log.warn("No entity types found in schema: ", namespace)
      goto continue
    end

    for _, entityType in ipairs(entityTypes) do
      local entityName = entityType:get_attribute("Name")
      kong.log.debug("Found entity type: ", entityName)
      
      local entity = {
        Name = entityName,
        Properties = {}
      }

      local properties = entityType:search("*[local-name()='Property']")
      if not properties or #properties == 0 then
        kong.log.warn("No properties found for entity type: ", entityName)
        goto continue_entity
      end

      for _, property in ipairs(properties) do
        local propName = property:get_attribute("Name")
        local propType = property:get_attribute("Type")
        local nullable = property:get_attribute("Nullable")
        
        kong.log.debug("Found property: ", propName, " of type ", propType)
        
        table.insert(entity.Properties, {
          Name = propName,
          Type = propType,
          Required = nullable == "false"
        })
      end

      table.insert(spec, entity)
      
      ::continue_entity::
    end
    ::continue::
  end

  if #spec == 0 then
    kong.log.err("Parsed specification is empty")
  end

  return spec
end

-- Function to map OData types to Lua types
function ODataValidationHandler:map_odata_type_to_lua(odata_type)
  local type_mapping = {
    ["Edm.Int32"] = "number",
    ["Edm.String"] = "string",
    -- Add more mappings as needed
  }
  return type_mapping[odata_type] or "string"
end

return ODataValidationHandler 