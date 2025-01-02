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
  local is_valid, validation_error = self:validate_odata_request(request_body, odata_specification, conf)

  if not is_valid then
    kong.log.err("Validation failed: ", validation_error)
    return kong.response.exit(400, { message = validation_error or "Request does not conform to OData specification" })
  end
end

-- Function to validate the request against the OData specification
function ODataValidationHandler:validate_odata_request(request_body, odata_specification, conf)
  -- Parse the OData specification
  local spec, err = self:parse_odata_specification(odata_specification)
  if err or not spec or #spec == 0 then
    kong.log.err("Failed to parse OData specification: ", err or "Specification is empty")
    return false, "Invalid OData specification"
  end

  -- Find matching entity type based on request body structure
  local rootEntityType = self:find_matching_entity_type(request_body, spec)
  if not rootEntityType then
    kong.log.err("No matching entity type found for request body")
    return false, "Request body does not match any known entity type"
  end

  kong.log.debug("Found matching entity type: ", rootEntityType.Name)
  -- Validate the request body against the root entity type
  return self:validate_entity(request_body, rootEntityType, spec)
end

-- Function to find matching entity type based on request body structure
function ODataValidationHandler:find_matching_entity_type(request_body, spec)
  -- Get the set of properties from the request body
  local request_properties = {}
  for key, _ in pairs(request_body) do
    request_properties[key] = true
  end

  -- Find entity type with best match
  local best_match = nil
  local best_match_score = 0

  for _, entity in ipairs(spec) do
    if not entity.IsComplexType then  -- Only consider entity types, not complex types
      local match_score = 0
      
      -- Count matching properties
      for _, prop in ipairs(entity.Properties) do
        if request_properties[prop.Name] then
          match_score = match_score + 1
        end
      end

      -- Update best match if this entity type has a better score
      -- We're no longer checking required properties here
      if match_score > best_match_score then
        best_match = entity
        best_match_score = match_score
      end
    end
  end

  -- If we found a match with at least one matching property
  if best_match and best_match_score > 0 then
    kong.log.debug("Found potential entity type match: ", best_match.Name, " with ", best_match_score, " matching properties")
    return best_match
  end

  return nil
end

-- Function to validate an entity against its type definition
function ODataValidationHandler:validate_entity(value, entityType, spec)
  kong.log.debug("Validating entity of type: ", entityType.Name)
  
  if type(value) ~= "table" then
    return false, "Expected object for type " .. entityType.Name
  end

  -- Validate each property
  for _, property in ipairs(entityType.Properties) do
    local propValue = value[property.Name]
    kong.log.debug("Checking property: ", property.Name)

    -- Check required fields
    if property.Required and propValue == nil then
      kong.log.err("Missing required field: ", property.Name)
      return false, "Missing required field: " .. property.Name
    end

    -- Skip validation for null optional fields
    if propValue == nil then
      goto continue
    end

    -- Handle different types of properties
    if property.IsNavigation then
      -- Handle navigation properties
      if property.Type:match("^Collection%(.*%)$") then
        if type(propValue) ~= "table" then
          return false, "Expected array for collection property " .. property.Name
        end
        -- Validate each item in the collection
        local itemType = property.Type:match("^Collection%((.*)%)$")
        for _, item in ipairs(propValue) do
          local valid, err = self:validate_complex_value(item, itemType, spec)
          if not valid then
            return false, err
          end
        end
      else
        -- Single navigation property
        local valid, err = self:validate_complex_value(propValue, property.Type, spec)
        if not valid then
          return false, err
        end
      end
    else
      -- Handle regular and complex type properties
      local expectedType = self:map_odata_type_to_lua(property.Type, entityType.Namespace)
      if type(propValue) ~= expectedType then
        kong.log.err("Field type mismatch for ", property.Name, ": expected ", property.Type, ", got ", type(propValue))
        return false, "Field " .. property.Name .. " must be of type " .. property.Type
      end

      -- If it's a complex type, validate its structure
      if expectedType == "table" then
        local valid, err = self:validate_complex_value(propValue, property.Type, spec)
        if not valid then
          return false, err
        end
      end
    end

    ::continue::
  end

  return true
end

-- Function to validate a complex value against its type
function ODataValidationHandler:validate_complex_value(value, typeName, spec)
  -- Find the type definition
  local typeEntity
  for _, entity in ipairs(spec) do
    if entity.Name == typeName:match("([^%.]+)$") then
      typeEntity = entity
      break
    end
  end

  if not typeEntity then
    kong.log.err("Type not found: ", typeName)
    return false, "Unknown type: " .. typeName
  end

  -- Validate against the found type
  return self:validate_entity(value, typeEntity, spec)
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

  -- If it's a complex type or entity type (contains namespace), it's a table
  if odata_type:find("%.") then
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