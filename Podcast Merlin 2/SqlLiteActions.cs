using Microsoft.Data.Sqlite;
using System;
using System.Collections.Generic;
using System.Data;
using System.IO;
using System.Threading.Tasks;
using Windows.Storage;
namespace PodMerForWinUi.Sql.SqlLite
{
    public class SqlLiteActions
    {
        public SqliteConnection sqldb;

        public SqlLiteActions()
        {
        }

        public async Task init()
        {
            await ApplicationData.Current.LocalFolder.CreateFileAsync("sqliteSample.db", CreationCollisionOption.OpenIfExists);
            string dbpath = Path.Combine(ApplicationData.Current.LocalFolder.Path,
                                         "sqliteSample.db");
            using (var db = new SqliteConnection($"Filename={dbpath}"))
            {
                db.Open();

                string tableCommand = "CREATE TABLE IF NOT " +
                    @"EXISTS Actions (	[ID] INTEGER PRIMARY KEY AUTOINCREMENT ,
    [podcast][Text] NULL,
	[episode][Text] NULL,
    [timestamp][nvarchar](8000) NULL,
    [guid][nvarchar](8000) NULL,
    [position][INTEGER] NULL,
    [started][INTEGER] NULL,
    [total][INTEGER] NULL,
    [action][nvarchar](8000) NULL);

";
                var createTable = new SqliteCommand(tableCommand, db);
                createTable.ExecuteReader();

                sqldb = db;
            }
        }
        public async Task<int> add(Action a)
        {
            await init();
            try
            {
                var cmd = $@"Insert into Actions (podcast, episode, timestamp, guid, position, started, total, action) 
VALUES ('{ExtraFunctions.reparse_string(a.podcast)}', '{a.episode}', '{a.timestamp}', '{a.guid}', {a.position}, {a.started}
, {a.total}, '{a.action}');";
                sqldb.Open();
                SqliteCommand insert_comd = new SqliteCommand(cmd, sqldb);
                if (await insert_comd.ExecuteNonQueryAsync() > 0)
                {
                    var Qury = $@"Select * from Actions where podcast = '{a.podcast}' And episode = '{a.episode}'
 And timestamp = '{a.timestamp}' And guid = '{a.guid}' And position = {a.position} And started = {a.started} 
And total = {a.total} And action = '{a.action}'";
                    var comd = new SqliteCommand(Qury, sqldb);
                    sqldb.Open();
                    var reader = await comd.ExecuteReaderAsync();
                    var dt = new DataTable();
                    dt.Load(reader);
                    return int.Parse(dt.Rows[dt.Rows.Count - 1]["ID"].ToString());
                }
                throw new Exception("adding action was unseccesfull");
            }
            catch
            {
                throw new Exception("adding action has caused an error");
            }
        }
        public async Task<List<Action>> get_all_actions()
        {
            await init();
            var Qury =
    $@"Select * from Actions;";
            SqliteCommand comd = new SqliteCommand(Qury, sqldb);
            sqldb.Open();
            var reader = await comd.ExecuteReaderAsync();
            var dt = new DataTable();
            dt.Load(reader);
            var Podcasts = new List<Action>();
            foreach (DataRow row in dt.Rows)
            {
                var action = new Action();
                action.ID = int.Parse(row["ID"].ToString());
                action.episode = row["episode"].ToString();
                action.timestamp = row["timestamp"].ToString();
                action.guid = row["guid"].ToString();
                action.position = int.Parse(row["position"].ToString());
                action.started = int.Parse(row["started"].ToString());
                action.total = int.Parse(row["total"].ToString());
                action.action = row["action"].ToString();
                Podcasts.Add(action);
            }
            return Podcasts;
        }
    }
}
