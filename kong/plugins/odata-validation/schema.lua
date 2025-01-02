return {
  name = "odata-validation",
  fields = {
    { config = {
        type = "record",
        fields = {
          { odata_schema_url = { type = "string", required = true, default = "" } },
          { odata_specification = { type = "string", required = true, default = "" } },
        },
      },
    },
  },
} 