# Kong plugin for validating requests against OData specifications

# About
This Kong 🦍 plugin validates incoming requests against an OData specification. It ensures that the request body matches the defined entity types, properties, and data types in the OData schema.

## Configuration parameters

| FORM PARAMETER | DEFAULT | DESCRIPTION |
|:--------------|:--------|:------------|
| config.odata_specification | nil | The OData specification XML that defines the schema for validation |

## Example configurations (deck YAML)

### Simple Example
```yaml
plugins:
- name: odata-validation
  config:
    odata_specification: |
      <?xml version="1.0" encoding="UTF-8"?>
      <edmx:Edmx Version="4.0" xmlns:edmx="http://docs.oasis-open.org/odata/ns/edmx">
        <edmx:DataServices>
          <Schema Namespace="ExampleModel" xmlns="http://docs.oasis-open.org/odata/ns/edm">
            <EntityType Name="Person">
              <Key>
                <PropertyRef Name="ID"/>
              </Key>
              <Property Name="ID" Type="Edm.Int32" Nullable="false"/>
              <Property Name="Name" Type="Edm.String" Nullable="false"/>
              <Property Name="Age" Type="Edm.Int32" Nullable="true"/>
            </EntityType>
          </Schema>
        </edmx:DataServices>
      </edmx:Edmx>
```

### Complex Example
```yaml
plugins:
- name: odata-validation
  config:
    odata_specification: |
      <?xml version="1.0" encoding="UTF-8"?>
      <edmx:Edmx Version="4.0" xmlns:edmx="http://docs.oasis-open.org/odata/ns/edmx">
        <edmx:DataServices>
          <Schema Namespace="UniversityModel" xmlns="http://docs.oasis-open.org/odata/ns/edm">
            <!-- Complex Types -->
            <ComplexType Name="Address">
              <Property Name="Street" Type="Edm.String" Nullable="false"/>
              <Property Name="City" Type="Edm.String" Nullable="false"/>
              <Property Name="PostalCode" Type="Edm.String" Nullable="false"/>
              <Property Name="Country" Type="Edm.String" Nullable="false"/>
            </ComplexType>
            <!-- Additional types omitted for brevity -->
          </Schema>
        </edmx:DataServices>
      </edmx:Edmx>
```

## Example Requests

### Simple Example
Valid request:
```bash
curl -X POST http://localhost:8000/odata \
  -H "Content-Type: application/json" \
  -d '\''{"ID": 1,"Name": "John Doe","Age": 30}'\''
```

Invalid request (missing required field):
```bash
curl -X POST http://localhost:8000/odata \
  -H "Content-Type: application/json" \
  -d '\''{"Name": "John Doe","Age": 30}'\''
```

### Complex Example
Valid request with nested objects:
```bash
curl -X POST http://localhost:8000/odata \
  -H "Content-Type: application/json" \
  -d '\''{"StudentID": 12345,"FirstName": "Jane","LastName": "Smith","EnrollmentDate": "2024-01-02T10:00:00Z","GPA": 3.85,"Status": "Active","Contact": {"Email": "jane.smith@university.edu","Phone": "+1-555-123-4567","Address": {"Street": "123 University Avenue","City": "College Town","PostalCode": "12345","Country": "United States"}}}'\''
```

## Features

- Validates request bodies against OData specifications
- Supports complex types and nested objects
- Handles collections and navigation properties
- Automatic entity type detection based on request structure
- Validates required fields and data types
- Supports EDM types (Int32, String, Boolean, Date, etc.)

## Supported OData Features

- Entity Types
- Complex Types
- Navigation Properties
- Collections
- Required/Optional Properties
- Basic EDM Types:
  - Edm.Int32
  - Edm.String
  - Edm.Decimal
  - Edm.Boolean
  - Edm.Date
  - Edm.DateTimeOffset

## Error Responses

The plugin returns 400 Bad Request with descriptive error messages for validation failures:

- Missing required fields
- Type mismatches
- Unknown entity types
- Invalid complex type structures

Example error response:
```json
{
  "message": "Missing required field: ID"
}
```
