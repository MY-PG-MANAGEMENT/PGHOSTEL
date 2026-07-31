package com.pgmanager.apilog;

import jakarta.persistence.Column;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.lang.reflect.Field;
import java.sql.Connection;
import java.sql.DatabaseMetaData;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.Statement;
import java.util.LinkedHashSet;
import java.util.Set;
import java.util.TreeSet;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Proves the baseline migration's {@code api_request_log} table runs on real PostgreSQL and that
 * its columns match the {@link ApiRequestLog} entity exactly.
 *
 * <p>This check earns its place because {@code ddl-auto} is {@code validate}: a single misspelled
 * column or a field with no column fails <em>application startup</em>, not a test — the most
 * expensive place to discover it. Comparing against the entity by reflection (rather than by
 * eyeballing the SQL) means the check keeps working as fields are added.
 *
 * <p>Before the PostgreSQL migration this test connected to a developer's local MySQL on 3306 and
 * skipped when none was listening — which meant it almost never ran, including in CI. It now uses
 * Testcontainers like the {@code integration} suites, so it skips only without Docker and does run
 * on every CI build (see {@code docs/TEST_PLAN.md}).
 */
@Testcontainers(disabledWithoutDocker = true)
class ApiRequestLogSchemaTest {

    @Container
    static final PostgreSQLContainer<?> POSTGRES =
            new PostgreSQLContainer<>("postgres:17-alpine").withDatabaseName("pg_manager");

    @Test
    void migrationSchemaMatchesTheEntity() throws Exception {
        Flyway.configure()
                .dataSource(POSTGRES.getJdbcUrl(), POSTGRES.getUsername(), POSTGRES.getPassword())
                .locations("classpath:db/migration")
                .load()
                .migrate();

        Set<String> actual = actualColumns();
        Set<String> expected = entityColumns();

        // Symmetric difference in both directions: a column the entity does not map is dead
        // weight, and a field with no column breaks startup.
        assertThat(actual).as("columns present in PostgreSQL but not mapped by the entity")
                .containsAll(expected);
        assertThat(expected).as("entity fields with no matching column")
                .containsAll(actual);

        assertThat(indexNames()).contains(
                "idx_arl_created_date", "idx_arl_org_created", "idx_arl_user_created",
                "idx_arl_request_uri", "idx_arl_status", "idx_arl_response_status_code",
                "idx_arl_app_version", "idx_arl_request_id");

        // The retention sweep's batched-delete form is PostgreSQL-specific (there is no
        // DELETE ... LIMIT) — execute it once for real so a syntax slip in
        // ApiRequestLogRepository.deleteBatchOlderThan cannot reach production.
        try (Connection connection = connect(); Statement statement = connection.createStatement()) {
            statement.executeUpdate(
                    "DELETE FROM api_request_log WHERE ctid IN (" +
                    "  SELECT ctid FROM api_request_log WHERE created_date < '2000-01-01' " +
                    "  ORDER BY created_date LIMIT 10 FOR UPDATE SKIP LOCKED)");
        }
    }

    /** The column names Hibernate will look for, read straight off the entity. */
    private Set<String> entityColumns() {
        Set<String> columns = new TreeSet<>();
        for (Field field : ApiRequestLog.class.getDeclaredFields()) {
            Column column = field.getAnnotation(Column.class);
            if (column != null) columns.add(column.name());
        }
        return columns;
    }

    private Set<String> actualColumns() throws Exception {
        Set<String> columns = new TreeSet<>();
        try (Connection connection = connect()) {
            DatabaseMetaData metaData = connection.getMetaData();
            // PostgreSQL's catalog is the database and the schema is "public" — the opposite
            // arrangement to MySQL, where the database WAS the schema argument.
            try (ResultSet rs = metaData.getColumns(null, "public", "api_request_log", null)) {
                while (rs.next()) columns.add(rs.getString("COLUMN_NAME").toLowerCase());
            }
        }
        return columns;
    }

    private Set<String> indexNames() throws Exception {
        Set<String> indexes = new LinkedHashSet<>();
        try (Connection connection = connect()) {
            try (ResultSet rs = connection.getMetaData()
                    .getIndexInfo(null, "public", "api_request_log", false, false)) {
                while (rs.next()) {
                    String name = rs.getString("INDEX_NAME");
                    if (name != null) indexes.add(name.toLowerCase());
                }
            }
        }
        return indexes;
    }

    private Connection connect() throws Exception {
        return DriverManager.getConnection(
                POSTGRES.getJdbcUrl(), POSTGRES.getUsername(), POSTGRES.getPassword());
    }
}
