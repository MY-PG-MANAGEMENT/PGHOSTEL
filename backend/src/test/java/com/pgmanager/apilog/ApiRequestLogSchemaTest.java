package com.pgmanager.apilog;

import jakarta.persistence.Column;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;

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
import static org.junit.jupiter.api.Assumptions.assumeTrue;

/**
 * Proves {@code V30__api_request_log.sql} runs on real MySQL and that its columns match the
 * {@link ApiRequestLog} entity exactly.
 *
 * <p>This check earns its place because {@code ddl-auto} is {@code validate}: a single misspelled
 * column or a field with no column fails <em>application startup</em>, not a test — the most
 * expensive place to discover it. Comparing against the entity by reflection (rather than by
 * eyeballing the SQL) means the check keeps working as fields are added.
 *
 * <p>Runs against a throwaway schema created and dropped in-test, so it never touches the
 * developer's {@code pg_manager} data. It skips cleanly when no local MySQL is listening, matching
 * how the Testcontainers suites skip without Docker (see {@code docs/TEST_PLAN.md}).
 */
class ApiRequestLogSchemaTest {

    private static final String HOST = "jdbc:mysql://localhost:3306/";
    private static final String SCHEMA = "pg_manager_apilog_schema_check";
    private static final String USER = "root";
    private static final String PASSWORD = "root";
    private static final String PARAMS = "?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Kolkata";

    @Test
    void migrationSchemaMatchesTheEntity() throws Exception {
        assumeTrue(mysqlReachable(), "local MySQL not reachable on 3306 - skipping schema check");

        try {
            createSchema();
            Flyway.configure()
                    .dataSource(HOST + SCHEMA + PARAMS, USER, PASSWORD)
                    .locations("classpath:db/migration")
                    .load()
                    .migrate();

            Set<String> actual = actualColumns();
            Set<String> expected = entityColumns();

            // Symmetric difference in both directions: a column the entity does not map is dead
            // weight, and a field with no column breaks startup.
            assertThat(actual).as("columns present in MySQL but not mapped by the entity")
                    .containsAll(expected);
            assertThat(expected).as("entity fields with no matching column")
                    .containsAll(actual);

            assertThat(indexNames()).contains(
                    "idx_arl_created_date", "idx_arl_org_created", "idx_arl_user_created",
                    "idx_arl_request_uri", "idx_arl_status", "idx_arl_response_status_code",
                    "idx_arl_app_version", "idx_arl_request_id");

            // The retention sweep's LIMIT syntax is MySQL-specific - execute it once for real.
            try (Connection connection = connect(SCHEMA); Statement statement = connection.createStatement()) {
                statement.executeUpdate(
                        "DELETE FROM api_request_log WHERE created_date < '2000-01-01' LIMIT 10");
            }
        } finally {
            dropSchema();
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
        try (Connection connection = connect(SCHEMA)) {
            DatabaseMetaData metaData = connection.getMetaData();
            try (ResultSet rs = metaData.getColumns(SCHEMA, null, "api_request_log", null)) {
                while (rs.next()) columns.add(rs.getString("COLUMN_NAME").toLowerCase());
            }
        }
        return columns;
    }

    private Set<String> indexNames() throws Exception {
        Set<String> indexes = new LinkedHashSet<>();
        try (Connection connection = connect(SCHEMA)) {
            try (ResultSet rs = connection.getMetaData()
                    .getIndexInfo(SCHEMA, null, "api_request_log", false, false)) {
                while (rs.next()) {
                    String name = rs.getString("INDEX_NAME");
                    if (name != null) indexes.add(name.toLowerCase());
                }
            }
        }
        return indexes;
    }

    private Connection connect(String schema) throws Exception {
        return DriverManager.getConnection(HOST + schema + PARAMS, USER, PASSWORD);
    }

    private void createSchema() throws Exception {
        try (Connection connection = connect(""); Statement statement = connection.createStatement()) {
            statement.executeUpdate("DROP DATABASE IF EXISTS " + SCHEMA);
            statement.executeUpdate("CREATE DATABASE " + SCHEMA);
        }
    }

    private void dropSchema() {
        try (Connection connection = connect(""); Statement statement = connection.createStatement()) {
            statement.executeUpdate("DROP DATABASE IF EXISTS " + SCHEMA);
        } catch (Exception ignored) {
            // Best effort: leaving a stray verification schema behind is not worth failing on.
        }
    }

    private boolean mysqlReachable() {
        try (Connection connection = connect("")) {
            return connection.isValid(2);
        } catch (Exception ignored) {
            return false;
        }
    }
}
