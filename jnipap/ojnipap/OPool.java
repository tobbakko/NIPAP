package ojnipap;

import java.math.BigDecimal;

import java.sql.SQLData;
import java.sql.SQLInput;
import java.sql.SQLOutput;
import java.sql.SQLException;

import oracle.sql.STRUCT;

import jnipap.Schema;
import jnipap.Pool;

/**
 * SQLObject version of the Pool class
 */
public class OPool extends jnipap.Pool implements SQLData {

	public void readSQL(SQLInput stream, String typeName) throws SQLException {

		// Read data from stream
		id = Helpers.integerOrNull(stream.readBigDecimal());
		name = stream.readString();
		schema = (jnipap.Schema)OSchema.fromSTRUCT((STRUCT)stream.readObject());
		description = stream.readString();
		default_type = stream.readString();
		ipv4_default_prefix_length = Helpers.integerOrNull(stream.readBigDecimal());
		ipv6_default_prefix_length = Helpers.integerOrNull(stream.readBigDecimal());

	}

	public void writeSQL(SQLOutput stream) throws SQLException {

		// Write data to stream
		stream.writeBigDecimal(Helpers.bigDecOrNull(id));
		stream.writeString(Helpers.strOrNull(name));
		stream.writeObject((OSchema)schema);
		stream.writeString(Helpers.strOrNull(description));
		stream.writeString(Helpers.strOrNull(default_type));
		stream.writeBigDecimal(Helpers.bigDecOrNull(ipv4_default_prefix_length));
		stream.writeBigDecimal(Helpers.bigDecOrNull(ipv6_default_prefix_length));

	}

	public String getSQLTypeName() {

		return "NIPAP_POOL";

	}

	/**
	 * Create OPool object from oracle.sql.STRUCT
	 *
	 * @param input STRUCT object contaning a NIPAP_POOL Oracle object
	 * @return An OPool instance
	 */
	static OPool fromSTRUCT(STRUCT input) throws SQLException {

		// If we received null, return a null pointer
		if (input == null) {
			return null;
		}

		// Create new OPool object from the STRUCT data
		OPool p = new OPool();
		Object[] val = input.getAttributes();
		p.id = Helpers.integerOrNull((BigDecimal)val[0]);
		p.name = (String)val[1];
		p.schema = (jnipap.Schema)OSchema.fromSTRUCT((STRUCT)val[2]);
		p.description = (String)val[3];
		p.default_type = (String)val[4];
		p.ipv4_default_prefix_length = Helpers.integerOrNull((BigDecimal)val[5]);
		p.ipv6_default_prefix_length = Helpers.integerOrNull((BigDecimal)val[6]);
		return p;

	}

}
