local cjson = require "cjson.safe"
local spec_parser = require "kong.plugins.odata-validation.spec_parsing"

local ODataValidationHandler = {
    PRIORITY = 1010, -- set the plugin priority, which determines plugin execution order
    VERSION = "0.1",
}

-- Add to the top with other local declarations
local enum_types = {}

-- Add basic_type_mapping as a local variable at the top
local basic_type_mapping = {
  ["Edm.Int32"] = "number",
  ["Edm.Int64"] = "number",
  ["Edm.String"] = "string",
  ["Edm.Decimal"] = "number",
  ["Edm.Single"] = "number",
  ["Edm.Double"] = "number",
  ["Edm.Boolean"] = "boolean",
  ["Edm.Date"] = "string",
  ["Edm.DateTimeOffset"] = "string",
  ["Edm.Guid"] = "string",
  ["Edm.Duration"] = "string",
  ["Edm.GeographyPoint"] = "table"
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

  local spec, err = spec_parser.parse(odata_specification, conf.specification_format)

  if err then
    kong.log.err("Failed to parse OData specification: ", err)
    return kong.response.exit(500, { message = err })
  end

  -- Log the full OData specification for debugging
  kong.log.debug("OData specification content: ", cjson.encode(spec))

  -- Implement the actual validation logic against the OData specification
  local is_valid, validation_error = self:validate_odata_request(request_body, spec, conf)

  if not is_valid then
    kong.log.err("Validation failed: ", validation_error)
    return kong.response.exit(400, { message = validation_error or "Request does not conform to OData specification" })
  end
end

-- Function to validate the request against the OData specification
function ODataValidationHandler:validate_odata_request(request_body, spec, conf)
  -- Remove the parsing step since spec is already parsed
  if not spec or #spec == 0 then
    kong.log.err("Specification is empty")
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
      if not basic_type_mapping[property.Type] then
        local valid, err = self:validate_complex_value(propValue, property.Type, spec)
        if not valid then
          return false, err
        end
      else
        -- Get expected Lua type
        local expectedType = basic_type_mapping[property.Type]
        local valueType = type(propValue)

        -- Special handling for numeric types
        if property.Type:match("^Edm%.Int%d+$") or 
           property.Type == "Edm.Decimal" or 
           property.Type == "Edm.Single" or 
           property.Type == "Edm.Double" then
          if valueType ~= "number" then
            kong.log.err("Field type mismatch for ", property.Name, ": expected number, got ", valueType)
            return false, "Field " .. property.Name .. " must be a number"
          end
          
          -- Additional validation for integer types
          if property.Type:match("^Edm%.Int%d+$") then
            if not spec_parser.validate_numeric(propValue, property.Type) then
              kong.log.err("Invalid integer value for ", property.Name)
              return false, "Field " .. property.Name .. " must be a valid integer"
            end
          end
        else
          -- Regular type validation for non-numeric types
          if valueType ~= expectedType then
            kong.log.err("Field type mismatch for ", property.Name, ": expected ", expectedType, ", got ", valueType)
            return false, "Field " .. property.Name .. " must be of type " .. property.Type
          end
        end
      end
    end

    ::continue::
  end

  return true
end

-- Function to validate a complex value against its type
function ODataValidationHandler:validate_complex_value(value, typeName, spec)
  -- Check if it's an enum type
  local enum_types = spec_parser.get_enum_types()
  if enum_types[typeName] then
    if type(value) ~= "string" then
      kong.log.err("Enum value must be a string for type ", typeName)
      return false, "Value must be a string enum value"
    end
    
    -- Check if the value is valid for this enum
    if not enum_types[typeName].values[value] then
      local valid_values = {}
      for val, _ in pairs(enum_types[typeName].values) do
        table.insert(valid_values, val)
      end
      kong.log.err("Invalid enum value for type ", typeName, ": ", value)
      return false, "Value must be one of: " .. table.concat(valid_values, ", ")
    end
    return true
  end

  -- Find the type definition for complex types
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
  -- Check if it's a collection type
  if odata_type:match("^Collection%(.*%)$") then
    return "table"
  end

  if spec_parser.basic_type_mapping[odata_type] then
    return spec_parser.basic_type_mapping[odata_type]
  end

  if odata_type:find("%.") then
    return "table"
  end

  return "string"
end

return ODataValidationHandler 