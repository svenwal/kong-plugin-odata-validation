return {
  name = "odata-validation",
  fields = {
    { config = {
        type = "record",
        fields = {
          { odata_specification = { type = "string", required = true } },
        },
      },
    },
  },
} 