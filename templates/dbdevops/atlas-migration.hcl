// Enterprise Atlas HCL Configuration for Declarative PostgreSQL Migrations
// Defines schema sources, ephemeral dev database for simulation, versioned migrations,
// and automated safety linting rules.

variable "db_url" {
  type    = string
  default = "postgres://postgres:password@localhost:5432/app_db?sslmode=disable"
}

env "local" {
  // Source schema defined in declarative SQL or HCL
  src = "file://schema.sql"

  // Target database URL for direct diff or application
  url = var.db_url

  // Ephemeral dev database container used by Atlas to simulate migrations
  dev = "docker://postgres/16/dev?search_path=public"

  migration {
    dir    = "file://migrations"
    format = atlas
  }

  // Safety checks during migration linting in CI
  lint {
    // Prohibit destructive operations (DROP TABLE, DROP COLUMN)
    destructive {
      error = true
    }

    // Prohibit operations that acquire heavy table locks
    concurrent_index {
      error = true
    }

    // Require non-null columns to have explicit defaults
    data_depend {
      error = true
    }
  }

  // Formatting and diff options
  diff {
    skip {
      drop_schema = true
    }
  }
}

env "production" {
  url = var.db_url
  dev = "docker://postgres/16/dev?search_path=public"

  migration {
    dir = "file://migrations"
  }

  lint {
    destructive {
      error = true
    }
    concurrent_index {
      error = true
    }
  }
}
