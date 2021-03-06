package jnipap;

import java.util.HashMap;
import java.util.Map;
import java.util.List;
import java.util.ArrayList;

import org.apache.xmlrpc.XmlRpcException;
import org.apache.xmlrpc.client.XmlRpcHttpTransportException;

import jnipap.NonExistentException;
import jnipap.ConnectionException;
import jnipap.AuthFailedException;
import jnipap.Connection;

public class Schema extends Jnipap {

	// Schema attributes
	public String name;
	public String description;
	public String vrf;

	/**
	 * Save object to NIPAP
	 *
	 * @param auth Authentication options
	 */
	public void save(Connection conn) throws JnipapException {

		// create hashmap of schema attributes
		HashMap attr = new HashMap();
		attr.put("name", this.name);
		attr.put("description", this.description);
		attr.put("vrf", this.vrf);

		// create schema spec
		HashMap schema_spec = new HashMap();
		schema_spec.put("id", this.id);

		// create args map
		HashMap args = new HashMap();
		args.put("auth", conn.authMap());
		args.put("attr", attr);

		// create params list
		List params = new ArrayList();
		params.add(args);

		// Create new or modify old?
		String cmd;
		if (this.id == null) {

			// ID null - create new schema
			cmd = "add_schema";

		} else {

			// Schema exists - modify existing.
			args.put("schema", schema_spec);
			cmd = "edit_schema";

		}

		// perform operation
		Integer result = (Integer)conn.execute(cmd, params);

		// If we added a new schema, fetch and set ID
		if (this.id == null) {
			this.id = result;
		}

	}

	/**
	 * Remove object from NIPAP
	 *
	 * @param auth Authentication options
	 */
	public void remove(Connection conn) throws JnipapException {

		// Build schema spec
		HashMap schema_spec = new HashMap();
		schema_spec.put("id", this.id);

		// Build function args
		HashMap args = new HashMap();
		args.put("auth", conn.authMap());
		args.put("schema", schema_spec);

		List params = new ArrayList();
		params.add(args);

		// execute query
		Object[] result = (Object[])conn.execute("remove_schema", params);

	}

	/**
	 * Return a string representation of a schema
	 *
	 * @return String describing the schema and its attributes
	 */
	public String toString() {

		// Return string representation of a schema
		return getClass().getName() + " id: " + this.id +
			" name: " + this.name +
			" desc: " + this.description +
			" vrf: " + this.vrf;

	}

	/**
	 * Get list of schemas from NIPAP by its attributes
	 *
	 * @param auth Authentication options
	 * @param query Map describing the search query
	 * @param search_options Search options
	 * @return A list of Schema objects matching the attributes in the schema_spec
	 */
	public static Map search(Connection conn, Map query, Map search_options) throws JnipapException {

		// Build function args
		HashMap args = new HashMap();
		args.put("auth", conn.authMap());
		args.put("query", query);
		args.put("search_options", search_options);

		List params = new ArrayList();
		params.add(args);

		// execute query
		Map result = (Map)conn.execute("search_schema", params);

		// extract data from result
		HashMap ret = new HashMap();
		ret.put("search_options", (Map)result.get("search_options"));
		ArrayList ret_schemas = new ArrayList();

		Object[] result_schemas = (Object[])result.get("result");

		for (int i = 0; i < result_schemas.length; i++) {
			Map result_schema = (Map)result_schemas[i];
			ret_schemas.add(Schema.fromMap(result_schema));
		}

		ret.put("result", ret_schemas);

		return ret;

	}

	/**
	 * Get list of schemas from NIPAP by a string
	 *
	 * @param auth Authentication options
	 * @param query Search string
	 * @param search_options Search options
	 * @return A list of Schema objects matching the attributes in the schema_spec
	 */
	public static Map search(Connection conn, String query, Map search_options) throws JnipapException {

		// Build function args
		HashMap args = new HashMap();
		args.put("auth", conn.authMap());
		args.put("query_string", query);
		args.put("search_options", search_options);

		List params = new ArrayList();
		params.add(args);

		// execute query
		Map result = (Map)conn.execute("smart_search_schema", params);

		// extract data from result
		HashMap ret = new HashMap();
		ret.put("search_options", (Map)result.get("search_options"));

		Object[] interpretation_result = (Object[])result.get("interpretation");
		List ret_interpretation = new ArrayList();
		for (int i = 0; i < interpretation_result.length; i++) {
			ret_interpretation.add((Map)interpretation_result[i]);
		}
		ret.put("interpretation", ret_interpretation);

		ArrayList ret_schemas = new ArrayList();
		Object[] result_schemas = (Object[])result.get("result");
		for (int i = 0; i < result_schemas.length; i++) {
			Map result_schema = (Map)result_schemas[i];
			ret_schemas.add(Schema.fromMap(result_schema));
		}
		ret.put("result", ret_schemas);

		return ret;

	}

	/**
	 * List schemas having specified attributes
	 *
	 * @param auth Authentication options
	 * @param schema_spec Map where attributes can be specified
	 */
	public static List list(Connection conn, Map schema_spec) throws JnipapException {

		// Build function args
		HashMap args = new HashMap();
		args.put("auth", conn.authMap());
		args.put("schema", schema_spec);

		List params = new ArrayList();
		params.add(args);

		// execute query
		Object[] result = (Object[])conn.execute("list_schema", params);

		// extract data from result
		ArrayList ret = new ArrayList();

		for (int i = 0; i < result.length; i++) {
			Map result_schema = (Map)result[i];
			ret.add(Schema.fromMap(result_schema));
		}

		return ret;

	}

	/**
	 * Get schema from NIPAP by ID
	 *
	 * Fetch the schema from NIPAP by specifying its ID. If no matching schema
	 * was found, an exception is thrown.
	 *
	 * @param auth Authentication options
	 * @param id ID of requested schema
	 * @return The schema which was found
	 */
	public static Schema get(Connection conn, Integer id) throws JnipapException {

		// Build schema spec
		HashMap schema_spec = new HashMap();
		schema_spec.put("id", id);

		List result = Schema.list(conn, schema_spec);

		// extract data from result
		if (result.size() < 1) {
			throw new NonExistentException("no matching schema found");
		}

		return (Schema)result.get(0);

	}

	/**
	 * Create schema object from map of schema attributes
	 *
	 * Helper function for creating objects of data received over XML-RPC
	 *
	 * @param input Map with schema attributes
	 * @return Schema object
	 */
	public static Schema fromMap(Map input) {

		Schema schema = new Schema();

		schema.id = (Integer)input.get("id");
		schema.name = (String)input.get("name");
		schema.description = (String)input.get("description");
		schema.vrf = (String)input.get("vrf");

		return schema;

	}

}
