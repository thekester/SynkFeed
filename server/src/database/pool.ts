import { Pool, type PoolClient, type QueryResult, type QueryResultRow } from "pg";

export interface Database {
  query<T extends QueryResultRow = QueryResultRow>(
    text: string,
    values?: readonly unknown[],
  ): Promise<QueryResult<T>>;
  transaction<T>(work: (client: PoolClient) => Promise<T>): Promise<T>;
  close(): Promise<void>;
}

export function createDatabase(connectionString: string): Database {
  const pool = new Pool({ connectionString });
  return {
    query: <T extends QueryResultRow = QueryResultRow>(
      text: string,
      values?: readonly unknown[],
    ) => pool.query<T>(text, values === undefined ? undefined : [...values]),
    async transaction<T>(work: (client: PoolClient) => Promise<T>): Promise<T> {
      const client = await pool.connect();
      try {
        await client.query("BEGIN");
        const result = await work(client);
        await client.query("COMMIT");
        return result;
      } catch (error) {
        await client.query("ROLLBACK");
        throw error;
      } finally {
        client.release();
      }
    },
    close: () => pool.end(),
  };
}
