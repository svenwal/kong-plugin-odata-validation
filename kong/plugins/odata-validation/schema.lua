return {
  name = "odata-validation",
  fields = {
    { config = {
        type = "record",
        fields = {
          { odata_schema_url = { type = "string", required = false } },
          { odata_specification = { type = "string", required = false } },
        },
      },
    },
  },
} 