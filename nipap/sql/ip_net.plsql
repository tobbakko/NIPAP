--------------------------------------------
--
-- The basic table structure and similar
--
--------------------------------------------

CREATE TYPE ip_net_plan_type AS ENUM ('reservation', 'assignment', 'host');

CREATE TYPE priority_3step AS ENUM ('low', 'medium', 'high');


--
-- This is where we store "schemas"
-- think of them as something like namespaces for our address plans
-- one would typically be the global one where all public addresses go
-- then we could have several for RFC1918 space to avoid collisions
--
CREATE TABLE ip_net_schema (
	id serial PRIMARY KEY,
	name text NOT NULL,
	description text,
	vrf text
);

CREATE UNIQUE INDEX ip_net_schema__name__index ON ip_net_schema (name);
CREATE UNIQUE INDEX ip_net_schema__vrf__index ON ip_net_schema (vrf);

COMMENT ON TABLE ip_net_schema IS 'IP Address schemas, something like namespaces for our address plan';
COMMENT ON INDEX ip_net_schema__name__index IS 'schema name';
COMMENT ON INDEX ip_net_schema__vrf__index IS 'schema VRF-id';


--
-- This table is used to store our pools. pools are for a specific
-- purpose and when you need a specific type of address, ie a core
-- loopback or similar, you'll just pick the right pool and get an
-- address assigned automatically.
--
CREATE TABLE ip_net_pool (
	id serial PRIMARY KEY,
	name text NOT NULL,
	schema integer NOT NULL REFERENCES ip_net_schema (id) ON UPDATE CASCADE ON DELETE CASCADE DEFAULT 1,
	description text,
	default_type ip_net_plan_type,
	ipv4_default_prefix_length integer,
	ipv6_default_prefix_length integer
);

CREATE UNIQUE INDEX ip_net_pool__schema_name__index ON ip_net_pool (schema, name);

COMMENT ON TABLE ip_net_pool IS 'IP Pools for assigning prefixes from';
COMMENT ON INDEX ip_net_pool__schema_name__index IS 'pool name';


--
-- this table stores the actual prefixes in the address plan, or net 
-- plan as I prefer to call it
--
-- pool is the pool for which this prefix is part of and from which 
-- assignments can be made
--
CREATE TABLE ip_net_plan (
	id serial PRIMARY KEY,
	schema integer NOT NULL REFERENCES ip_net_schema (id) ON UPDATE CASCADE ON DELETE CASCADE DEFAULT 1,
	prefix cidr NOT NULL,
	display_prefix inet,
	description text,
	comment text,
	node text,
	pool integer REFERENCES ip_net_pool (id) ON UPDATE CASCADE ON DELETE SET NULL,
	type ip_net_plan_type NOT NULL,
	indent integer,
	country text,
	order_id text,
	vrf text,
	external_key text,
	authoritative_source text NOT NULL,
	alarm_priority priority_3step,
	monitor boolean
);

COMMENT ON TABLE ip_net_plan IS 'Actual address / prefix plan';

COMMENT ON COLUMN ip_net_plan.schema IS 'Address-schema';
COMMENT ON COLUMN ip_net_plan.prefix IS '"true" IP prefix, with hosts registered as /32';
COMMENT ON COLUMN ip_net_plan.display_prefix IS 'IP prefix with hosts having their covering assignments prefix-length';
COMMENT ON COLUMN ip_net_plan.description IS 'Prefix description';
COMMENT ON COLUMN ip_net_plan.comment IS 'Comment!';
COMMENT ON COLUMN ip_net_plan.node IS 'FQDN of the IP node where the prefix is/should be configured on';
COMMENT ON COLUMN ip_net_plan.pool IS 'Pool that this prefix is part of';
COMMENT ON COLUMN ip_net_plan.type IS 'Type is one of "reservation", "assignment" or "host"';
COMMENT ON COLUMN ip_net_plan.indent IS 'Number of indents to properly render this prefix';
COMMENT ON COLUMN ip_net_plan.country IS 'ISO3166-1 two letter country code';
COMMENT ON COLUMN ip_net_plan.order_id IS 'Order identifier';
COMMENT ON COLUMN ip_net_plan.vrf IS 'VRF in which the prefix resides';
COMMENT ON COLUMN ip_net_plan.external_key IS 'Field for use by exernal systems which need references to its own dataset.';
COMMENT ON COLUMN ip_net_plan.authoritative_source IS 'The authoritative source for information regarding this prefix';
COMMENT ON COLUMN ip_net_plan.alarm_priority IS 'Priority of alarms sent for this prefix to NetWatch.';
COMMENT ON COLUMN ip_net_plan.monitor IS 'Whether the prefix should be monitored or not.';

CREATE UNIQUE INDEX ip_net_plan__schema_prefix__index ON ip_net_plan (schema, prefix);

COMMENT ON INDEX ip_net_plan__schema_prefix__index IS 'prefix';
CREATE INDEX ip_net_plan__schema__index ON ip_net_plan (schema);
CREATE INDEX ip_net_plan__node__index ON ip_net_plan (node);
CREATE INDEX ip_net_plan__family__index ON ip_net_plan (family(prefix));
CREATE INDEX ip_net_plan__prefix_iprange_index ON ip_net_plan USING gist(iprange(prefix));

--
-- Audit log table
--
CREATE TABLE ip_net_log (
	id serial PRIMARY KEY,
	schema_name TEXT,
	schema INTEGER,
	prefix_prefix cidr,
	prefix INTEGER,
	pool_name TEXT,
	pool INTEGER,
	timestamp TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
	username TEXT NOT NULL,
	authenticated_as TEXT NOT NULL,
	authoritative_source TEXT NOT NULL,
	full_name TEXT,
	description TEXT NOT NULL
);

COMMENT ON TABLE ip_net_log IS 'Log of changes made to tables';

COMMENT ON COLUMN ip_net_log.schema_name IS 'Name of affected schema, or schema of affected prefix';
COMMENT ON COLUMN ip_net_log.schema IS 'ID of affected schema, or schema of affected prefix';
COMMENT ON COLUMN ip_net_log.prefix_prefix IS 'Prefix which was affected of the action';
COMMENT ON COLUMN ip_net_log.prefix IS 'ID of affected prefix';
COMMENT ON COLUMN ip_net_log.pool_name IS 'Name of affected pool';
COMMENT ON COLUMN ip_net_log.pool IS 'ID of affected pool';
COMMENT ON COLUMN ip_net_log.timestamp IS 'Time when the change was made';
COMMENT ON COLUMN ip_net_log.username IS 'Username of the user who made the change';
COMMENT ON COLUMN ip_net_log.authenticated_as IS 'Username of user who authenticated the change. This can be a real person or a system which is trusted to perform operations in another users name.';
COMMENT ON COLUMN ip_net_log.authoritative_source IS 'System from which the action was made';
COMMENT ON COLUMN ip_net_log.full_name IS 'Full name of the user who is responsible for the action';
COMMENT ON COLUMN ip_net_log.description IS 'Text describing the action';

CREATE INDEX ip_net_log__schema__index ON ip_net_log(schema);
CREATE INDEX ip_net_log__prefix__index ON ip_net_log(prefix);
CREATE INDEX ip_net_log__pool__index ON ip_net_log(pool);


CREATE OR REPLACE FUNCTION tf_ip_net_prefix_iu_before() RETURNS trigger AS $_$
DECLARE
	parent RECORD;
	child RECORD;
	i_max_pref_len integer;
BEGIN
	-- this is a shortcut to avoid running the rest of this trigger as it
	-- can be fairly costly performance wise
	--
	-- sanity checking is done on 'type' and derivations of 'prefix' so if
	-- those stay the same, we don't need to run the rest of the sanity
	-- checks.
	IF TG_OP = 'UPDATE' THEN
		-- we need to nest cause plpgsql is stupid :(
		IF OLD.type = NEW.type AND OLD.prefix = NEW.prefix THEN
			RETURN NEW;
		END IF;
	END IF;


	i_max_pref_len := 32;
	IF family(NEW.prefix) = 6 THEN
		i_max_pref_len := 128;
	END IF;
	-- contains the parent prefix
	SELECT * INTO parent FROM ip_net_plan WHERE schema = NEW.schema AND iprange(prefix) >> iprange(NEW.prefix) ORDER BY masklen(prefix) DESC LIMIT 1;

	-- check that type is correct on insert and update
	IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
		IF NEW.type = 'host' THEN
			IF masklen(NEW.prefix) != i_max_pref_len THEN
				RAISE EXCEPTION '1200:Prefix of type host must have all bits set in netmask';
			END IF;
			IF parent.prefix IS NULL THEN
				RAISE EXCEPTION '1200:Prefix of type host must have a parent (covering) prefix of type assignment';
			END IF;
			IF parent.type != 'assignment' THEN
				RAISE EXCEPTION '1200:Parent prefix (%) is of type % but must be of type ''assignment''', parent.prefix, parent.type;
			END IF;
			NEW.display_prefix := set_masklen(NEW.prefix::inet, masklen(parent.prefix));
		ELSIF NEW.type = 'assignment' THEN
			IF parent.type IS NULL THEN
				-- all good
			ELSIF parent.type != 'reservation' THEN
				RAISE EXCEPTION '1200:Parent prefix (%) is of type % but must be of type ''reservation''', parent.prefix, parent.type;
			END IF;
			NEW.display_prefix := NEW.prefix;
		ELSIF NEW.type = 'reservation' THEN
			IF parent.type IS NULL THEN
				-- all good
			ELSIF parent.type != 'reservation' THEN
				RAISE EXCEPTION '1200:Parent prefix (%) is of type % but must be of type ''reservation''', parent.prefix, parent.type;
			END IF;
			NEW.display_prefix := NEW.prefix;
		ELSE
			RAISE EXCEPTION 'Unknown prefix type';
		END IF;
	END IF;

	-- don't allow changing of type
	IF TG_OP = 'UPDATE' THEN
		IF OLD.type != NEW.type THEN
			-- FIXME: better exception code
			RAISE EXCEPTION '1200:Changing type is disallowed';
		END IF;
	END IF;

	RETURN NEW;
END;
$_$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION tf_ip_net_prefix_d_before() RETURNS trigger AS $_$
BEGIN
	-- prevent certain deletes to maintain DB integrity
	IF TG_OP = 'DELETE' THEN
		-- if an assignment contains hosts, we block the delete
		IF OLD.type = 'assignment' THEN
			-- contains one child prefix
			-- FIXME: optimize with this, what is improvement?
			-- IF (SELECT COUNT(1) FROM ip_net_plan WHERE prefix << OLD.prefix LIMIT 1) > 0 THEN
			IF (SELECT COUNT(1) FROM ip_net_plan WHERE prefix << OLD.prefix AND schema = OLD.schema) > 0 THEN
				RAISE EXCEPTION '1200:Disallowed delete, prefix (%) contains hosts.', OLD.prefix;
			END IF;
		END IF;
		-- everything else is allowed
	END IF;

	RETURN OLD;
END;
$_$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_ip_net_plan_prefix__iu_before
	BEFORE UPDATE OR INSERT
	ON ip_net_plan
	FOR EACH ROW
	EXECUTE PROCEDURE tf_ip_net_prefix_iu_before();

CREATE TRIGGER trigger_ip_net_plan_prefix__d_before
	BEFORE DELETE
	ON ip_net_plan
	FOR EACH ROW
	EXECUTE PROCEDURE tf_ip_net_prefix_d_before();


CREATE OR REPLACE FUNCTION tf_ip_net_prefix_family_after() RETURNS trigger AS $$
DECLARE
	r RECORD;
BEGIN
	IF TG_OP = 'DELETE' THEN
		PERFORM calc_indent(OLD.schema, OLD.prefix, -1);
	ELSIF TG_OP = 'INSERT' THEN
		PERFORM calc_indent(NEW.schema, NEW.prefix, 1);
	ELSE
		-- nothing!
	END IF;
	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_ip_net_plan_prefix__iu_after
	AFTER DELETE OR INSERT OR UPDATE
	ON ip_net_plan
	FOR EACH ROW
	EXECUTE PROCEDURE tf_ip_net_prefix_family_after();

