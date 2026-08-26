import java.io.BufferedWriter;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.CallableStatement;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/**
 * Exports deterministic Oracle table, index and comment metadata without reading business rows.
 */
public final class OracleDdlSnapshot {

    private static final String JDBC_URL_ENV = "YOOONI_DDL_JDBC_URL";
    private static final String USERNAME_ENV = "YOOONI_DDL_USERNAME";
    private static final String PASSWORD_ENV = "YOOONI_DDL_PASSWORD";

    private OracleDdlSnapshot() {
    }

    /**
     * Connects to Oracle and writes a stable Markdown snapshot.
     *
     * @param args output path and schema name
     * @throws Exception when any metadata object cannot be exported
     */
    public static void main(String[] args) throws Exception {
        if (args.length != 2) {
            throw new IllegalArgumentException("Usage: OracleDdlSnapshot <output> <schema>");
        }
        String schema = validateSchema(args[1]);
        String jdbcUrl = requireEnvironment(JDBC_URL_ENV);
        String username = requireEnvironment(USERNAME_ENV);
        String password = requireEnvironment(PASSWORD_ENV);
        Path output = Path.of(args[0]).toAbsolutePath().normalize();

        Class.forName("oracle.jdbc.driver.OracleDriver");
        try (Connection connection = DriverManager.getConnection(jdbcUrl, username, password)) {
            configureMetadata(connection);
            List<String> tables = loadTableNames(connection);
            if (tables.isEmpty()) {
                throw new SQLException("Oracle schema returned zero tables");
            }
            writeSnapshot(connection, output, schema, tables);
            System.out.println("DDL snapshot exported: tables=" + tables.size());
        }
    }

    private static String validateSchema(String value) {
        String schema = value == null ? "" : value.trim().toUpperCase(Locale.ROOT);
        if (!schema.matches("[A-Z][A-Z0-9_$#]{0,127}")) {
            throw new IllegalArgumentException("Invalid Oracle schema name");
        }
        return schema;
    }

    private static String requireEnvironment(String name) {
        String value = System.getenv(name);
        if (value == null || value.isBlank()) {
            throw new IllegalStateException("Missing required environment variable: " + name);
        }
        return value;
    }

    private static void configureMetadata(Connection connection) throws SQLException {
        String block = "BEGIN "
                + "DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM,'SQLTERMINATOR',TRUE); "
                + "DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM,'SEGMENT_ATTRIBUTES',FALSE); "
                + "DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM,'STORAGE',FALSE); "
                + "END;";
        try (CallableStatement statement = connection.prepareCall(block)) {
            statement.execute();
        }
    }

    private static List<String> loadTableNames(Connection connection) throws SQLException {
        List<String> names = new ArrayList<>();
        try (PreparedStatement statement = connection.prepareStatement(
                "SELECT table_name FROM user_tables ORDER BY table_name");
             ResultSet result = statement.executeQuery()) {
            while (result.next()) {
                names.add(result.getString(1));
            }
        }
        return names;
    }

    private static void writeSnapshot(Connection connection, Path output, String schema, List<String> tables)
            throws SQLException, IOException {
        Files.createDirectories(output.getParent());
        try (BufferedWriter writer = Files.newBufferedWriter(output, StandardCharsets.UTF_8)) {
            writer.write("<!-- DDL-SNAPSHOT-TABLE-COUNT: " + tables.size() + " -->\n\n");
            writer.write("## table list (real dump, alpha, total " + tables.size() + ")\n\n");
            for (String table : tables) {
                writer.write("- `" + table + "`\n");
            }
            for (String table : tables) {
                writeTable(connection, writer, schema, table);
            }
        }
    }

    private static void writeTable(Connection connection, BufferedWriter writer, String schema, String table)
            throws SQLException, IOException {
        writer.write("\n---\n\n## " + table + "\n\n```sql\n");
        writer.write(fetchDdl(connection, "TABLE", table, schema).trim());
        writer.write("\n");
        for (String index : loadIndexNames(connection, table)) {
            writer.write("\n");
            writer.write(fetchDdl(connection, "INDEX", index, schema).trim());
            writer.write("\n");
        }
        writeComments(connection, writer, schema, table);
        writer.write("```\n");
    }

    private static String fetchDdl(Connection connection, String objectType, String objectName, String schema)
            throws SQLException {
        String sql = "SELECT DBMS_METADATA.GET_DDL(?, ?, ?) FROM dual";
        try (PreparedStatement statement = connection.prepareStatement(sql)) {
            statement.setString(1, objectType);
            statement.setString(2, objectName);
            statement.setString(3, schema);
            try (ResultSet result = statement.executeQuery()) {
                if (!result.next() || result.getString(1) == null) {
                    throw new SQLException("Missing DDL for " + objectType + " " + objectName);
                }
                return result.getString(1);
            }
        }
    }

    private static List<String> loadIndexNames(Connection connection, String table) throws SQLException {
        List<String> names = new ArrayList<>();
        String sql = "SELECT index_name FROM user_indexes "
                + "WHERE table_name = ? AND generated = 'N' AND index_type <> 'LOB' ORDER BY index_name";
        try (PreparedStatement statement = connection.prepareStatement(sql)) {
            statement.setString(1, table);
            try (ResultSet result = statement.executeQuery()) {
                while (result.next()) {
                    names.add(result.getString(1));
                }
            }
        }
        return names;
    }

    private static void writeComments(Connection connection, BufferedWriter writer, String schema, String table)
            throws SQLException, IOException {
        String tableComment = loadTableComment(connection, table);
        if (tableComment != null && !tableComment.isBlank()) {
            writer.write("\nCOMMENT ON TABLE " + identifier(schema) + "." + identifier(table)
                    + " IS '" + literal(tableComment) + "';\n");
        }
        String sql = "SELECT column_name, comments FROM user_col_comments "
                + "WHERE table_name = ? AND comments IS NOT NULL ORDER BY column_name";
        try (PreparedStatement statement = connection.prepareStatement(sql)) {
            statement.setString(1, table);
            try (ResultSet result = statement.executeQuery()) {
                while (result.next()) {
                    writer.write("\nCOMMENT ON COLUMN " + identifier(schema) + "." + identifier(table) + "."
                            + identifier(result.getString(1)) + " IS '" + literal(result.getString(2)) + "';\n");
                }
            }
        }
    }

    private static String loadTableComment(Connection connection, String table) throws SQLException {
        try (PreparedStatement statement = connection.prepareStatement(
                "SELECT comments FROM user_tab_comments WHERE table_name = ?")) {
            statement.setString(1, table);
            try (ResultSet result = statement.executeQuery()) {
                return result.next() ? result.getString(1) : null;
            }
        }
    }

    private static String identifier(String value) {
        return "\"" + value.replace("\"", "\"\"") + "\"";
    }

    private static String literal(String value) {
        return value.replace("'", "''").replace("\r", " ").replace("\n", " ");
    }
}
