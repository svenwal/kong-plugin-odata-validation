local cjson = require "cjson.safe"
local xmlua = require "xmlua"

-- Local declarations
local enum_types = {}

-- Basic type mapping
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

local SpecParser = {}

-- Function to parse JSON specification
function SpecParser:parse_json_specification(json_spec)
    local spec = {}
    
    -- Parse JSON
    local parsed_json, err = cjson.decode(json_spec)
    if err then
        kong.log.err("Failed to parse JSON specification: ", err)
        return nil, "Invalid JSON specification"
    end

    -- Validate JSON structure
    if not parsed_json["$Version"] then
        return nil, "Invalid OData JSON specification: missing $Version"
    end

    -- Process schema definitions
    for namespace, schema in pairs(parsed_json) do
        if type(schema) == "table" and namespace ~= "$Version" and namespace ~= "$Reference" then
            -- First process enum types
            for typename, typedef in pairs(schema) do
                if type(typedef) == "table" and typedef["$Kind"] == "EnumType" then
                    local fullName = namespace .. "." .. typename
                    enum_types[fullName] = {
                        values = {}
                    }

                    -- Process enum members
                    for memberName, memberDef in pairs(typedef) do
                        if type(memberDef) == "table" and memberDef["$Value"] then
                            enum_types[fullName].values[memberName] = memberDef["$Value"]
                        end
                    end
                end
            end

            -- Process complex types
            for typename, typedef in pairs(schema) do
                if type(typedef) == "table" and typedef["$Kind"] == "ComplexType" then
                    local entity = {
                        Name = typename,
                        Properties = {},
                        IsComplexType = true,
                        Namespace = namespace
                    }

                    -- Process properties
                    for propname, propdef in pairs(typedef) do
                        if type(propdef) == "table" and propname ~= "$Kind" then
                            local isNavigation = propdef["$Kind"] == "NavigationProperty"
                            table.insert(entity.Properties, {
                                Name = propname,
                                Type = propdef["$Type"] or "Edm.String",
                                Required = not isNavigation and not (propdef["$Nullable"] or false),
                                IsNavigation = isNavigation
                            })
                        end
                    end

                    table.insert(spec, entity)
                end
            end

            -- Process entity types
            for typename, typedef in pairs(schema) do
                if type(typedef) == "table" and typedef["$Kind"] == "EntityType" then
                    local entity = {
                        Name = typename,
                        Properties = {},
                        Key = typedef["$Key"] or {},
                        IsComplexType = false,
                        Namespace = namespace
                    }

                    -- Process properties
                    for propname, propdef in pairs(typedef) do
                        if type(propdef) == "table" and propname ~= "$Kind" and propname ~= "$Key" then
                            local isNavigation = propdef["$Kind"] == "NavigationProperty"
                            table.insert(entity.Properties, {
                                Name = propname,
                                Type = propdef["$Type"] or "Edm.String",
                                Required = not isNavigation and not (propdef["$Nullable"] or false),
                                IsNavigation = isNavigation
                            })
                        end
                    end

                    table.insert(spec, entity)
                end
            end
        end
    end

    if #spec == 0 then
        kong.log.err("Parsed JSON specification is empty")
    end

    return spec
end

-- Function to parse XML specification
function SpecParser:parse_xml_specification(xml_spec)
    kong.log.debug("Parsing OData specification...")
    
    local document, parse_err = xmlua.XML.parse(xml_spec)
    if parse_err then
        kong.log.err("XML parsing error: ", parse_err)
        return nil, "XML parsing error"
    end

    local root = document:root()
    kong.log.debug("Root element name: ", root:name())

    -- Find all Schema elements
    local schemas = root:search("//Schema")
    local spec = {}

    -- Process each schema
    for _, schema in ipairs(schemas) do
        local namespace = schema:get_attribute("Namespace")
        kong.log.debug("Processing schema with namespace: ", namespace)

        -- First process EnumTypes
        local enumTypes = schema:search("*[local-name()='EnumType']")
        for _, enumType in ipairs(enumTypes) do
            local enumName = enumType:get_attribute("Name")
            local fullName = namespace .. "." .. enumName
            enum_types[fullName] = {
                values = {}
            }

            local members = enumType:search("*[local-name()='Member']")
            for _, member in ipairs(members) do
                local memberName = member:get_attribute("Name")
                local memberValue = member:get_attribute("Value")
                enum_types[fullName].values[memberName] = memberValue or #enum_types[fullName].values
            end
        end

        -- Process ComplexTypes
        local complexTypes = schema:search("*[local-name()='ComplexType']")
        for _, complexType in ipairs(complexTypes) do
            local entity = {
                Name = complexType:get_attribute("Name"),
                Properties = {},
                IsComplexType = true,
                Namespace = namespace
            }

            -- Process properties
            local properties = complexType:search("*[local-name()='Property']")
            for _, prop in ipairs(properties) do
                table.insert(entity.Properties, {
                    Name = prop:get_attribute("Name"),
                    Type = prop:get_attribute("Type"),
                    Required = prop:get_attribute("Nullable") ~= "true"
                })
            end

            table.insert(spec, entity)
        end

        -- Process EntityTypes
        local entityTypes = schema:search("*[local-name()='EntityType']")
        for _, entityType in ipairs(entityTypes) do
            local entity = {
                Name = entityType:get_attribute("Name"),
                Properties = {},
                Key = {},
                IsComplexType = false,
                Namespace = namespace
            }

            -- Process key fields
            local keys = entityType:search("*[local-name()='Key']/*[local-name()='PropertyRef']")
            for _, key in ipairs(keys) do
                table.insert(entity.Key, key:get_attribute("Name"))
            end

            -- Process properties
            local properties = entityType:search("*[local-name()='Property']")
            for _, prop in ipairs(properties) do
                table.insert(entity.Properties, {
                    Name = prop:get_attribute("Name"),
                    Type = prop:get_attribute("Type"),
                    Required = prop:get_attribute("Nullable") ~= "true"
                })
            end

            -- Process navigation properties
            local navProperties = entityType:search("*[local-name()='NavigationProperty']")
            for _, navProp in ipairs(navProperties) do
                table.insert(entity.Properties, {
                    Name = navProp:get_attribute("Name"),
                    Type = navProp:get_attribute("Type"),
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

-- Function to parse OData specification
function SpecParser:parse_odata_specification(odata_specification, format)
    kong.log.debug("Parsing OData specification...")
    
    -- Auto-detect format if not specified
    if not format or format == "auto" then
        -- Check if it starts with { for JSON
        if odata_specification:match("^%s*{") then
            format = "json"
        -- Check if it starts with < or <?xml for XML
        elseif odata_specification:match("^%s*<%??") then
            format = "xml"
        else
            return nil, "Unable to auto-detect specification format"
        end
    end

    if format == "json" then
        return self:parse_json_specification(odata_specification)
    else
        return self:parse_xml_specification(odata_specification)
    end
end

-- Function to validate numeric type
function SpecParser:validate_numeric_type(value, edmType)
    if type(value) ~= "number" then
        return false
    end

    -- Validate number ranges
    if edmType == "Edm.Int32" then
        return value >= -2147483648 and value <= 2147483647 and math.floor(value) == value
    elseif edmType == "Edm.Int64" then
        -- Lua numbers can safely represent integers up to 2^53
        return math.floor(value) == value
    elseif edmType == "Edm.Single" or edmType == "Edm.Double" or edmType == "Edm.Decimal" then
        -- Allow any number for floating point types
        return true
    end

    return true
end

-- Export the module
return {
    parse = function(spec, format)
        return SpecParser:parse_odata_specification(spec, format)
    end,
    validate_numeric = function(value, edmType)
        return SpecParser:validate_numeric_type(value, edmType)
    end,
    basic_type_mapping = basic_type_mapping,
    get_enum_types = function()
        return enum_types
    end
} 