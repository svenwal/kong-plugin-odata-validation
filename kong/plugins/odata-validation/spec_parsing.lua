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
    -- ... existing parse_json_specification code ...
end

-- Function to parse XML specification
function SpecParser:parse_xml_specification(xml_spec)
    -- ... existing parse_xml_specification code ...
end

-- Function to parse OData specification
function SpecParser:parse_odata_specification(odata_specification, format)
    -- ... existing parse_odata_specification code ...
end

-- Function to validate numeric type
function SpecParser:validate_numeric_type(value, edmType)
    -- ... existing validate_numeric_type code ...
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