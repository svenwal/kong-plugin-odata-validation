return {
  name = "odata-validation",
  fields = {
    { config = {
        type = "record",
        fields = {
          { odata_specification = { 
              type = "string", 
              required = true,
              description = "OData specification in XML or JSON format" 
          }},
          { specification_format = {
              type = "string",
              required = false,
              default = "auto",
              one_of = { "auto", "xml", "json" },
              description = "Format of the OData specification - auto will try to detect based on content"
          }},
        },
      },
    },
  },
} 