using Microsoft.Data.Sqlite;
using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.Collections.ObjectModel;
using System.Data;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Windows.Storage;

namespace PodMerForWinUi.Sql.SqlLite
{
    public static class ExtraFunctions
    {
        //public static string reparse_string(string str)
        //{
        //    return str.Replace("'", "''");
        //}
        public static Func<string, string> reparse_string = str => str.Replace("'", "''");
        public static Func<DateTimeOffset, string> reparseTime = time => time.DateTime.ToString("yyyy-MM-dd HH:mm:ss");
    }
    public class SqlLitePodcastsShows
    {
        public SqliteConnection sqldb;

        public SqlLitePodcastsShows()
        {
        }

        public async Task initAsync()
        {
            await ApplicationData.Current.LocalFolder.CreateFileAsync("sqliteSample.db", CreationCollisionOption.OpenIfExists);
            string dbpath = Path.Combine(ApplicationData.Current.LocalFolder.Path,
                                         "sqliteSample.db");
            using (var db = new SqliteConnection($"Filename={dbpath}"))
            {
                db.Open();

                string tableCommand = "CREATE TABLE IF NOT " +
                    @"EXISTS PodcastShows (	[ID] INTEGER PRIMARY KEY AUTOINCREMENT ,
    [Name][nvarchar](8000) NULL,
	[PlayUrl][Text](8000) NULL,
    [Published][DateTime] NULL,
    [Discription][TEXT] NULL,
    [Position][INTEGER] NULL,
    [Total][INTEGER] NULL,
    [Started][INTEGER] NULL,
    [ThumbnailIconUrl][TEXT] NULL,
    [PublishedDate][INTEGER] NULL,
    [PodcastID][INTEGER] NOT NULL,
    FOREIGN KEY (PodcastID)
       REFERENCES Podcasts (ID) 
);
";
                var createTable = new SqliteCommand(tableCommand, db);
                createTable.ExecuteReader();

                sqldb = db;
            }
        }

        public async Task<int> add(PodcastApesode a)
        {
            await initAsync();
            try
            {


                var Qury = $@"Select * from PodcastShows where Name = '{ExtraFunctions.reparse_string(a.Name)}' and ( PlayUrl = '{a.PlayUrl}' OR Discription = '{ExtraFunctions.reparse_string(a.Discription)}')";
                SqliteCommand comd = new SqliteCommand(Qury, sqldb);
                sqldb.Open();
                var reader = await comd.ExecuteReaderAsync();
                var dt = new DataTable();
                dt.Load(reader);

                if (dt.Rows.Count <= 0)
                {
                    var cmd = getInsertString(a);
                    sqldb.Open();
                    SqliteCommand insert_comd = new SqliteCommand(cmd, sqldb);

                    if (await insert_comd.ExecuteNonQueryAsync() > 0)
                    {
                        Qury = $@"Select * from PodcastShows where Name = '{a.Name.Replace("'", "''")}' and ( PlayUrl = '{a.PlayUrl}' OR Discription = '{ExtraFunctions.reparse_string(a.Discription)}')";
                        comd = new SqliteCommand(Qury, sqldb);
                        sqldb.Open();
                        reader = await comd.ExecuteReaderAsync();
                        dt = new DataTable();
                        dt.Load(reader);
                        return int.Parse(dt.Rows[dt.Rows.Count - 1]["ID"].ToString());
                    }
                }
            }
            catch
            {
                throw new Exception("adding podcasts has caused an error");
            }
            throw new Exception("podcast already exists");
        }
        private string getInsertString(PodcastApesode show)
        {
            return $@"Insert into PodcastShows (Name, PlayUrl, Published, Discription, Position, PodcastID, Total, Started) VALUES ('{show.Name.Replace("'", "''")}', '{show.PlayUrl}', '{show.Published.DateTime.ToString("yyyy-MM-dd HH:mm:ss")}', '{ExtraFunctions.reparse_string(show.Discription)}', '{show.Position}', {show.PodcastID}, {show.Total}, {show.Started});";

        }
        private string getUpdateString(PodcastApesode show)
        {
            return $@"update PodcastShows set Name = '{ExtraFunctions.reparse_string(show.Name)}', PlayUrl= '{show.PlayUrl}', Published = '{show.Published.DateTime.ToString("yyyy-MM-dd HH:mm:ss")}' , Discription = '{ExtraFunctions.reparse_string(show.Discription)}', Position = {show.Position} , PodcastID = {show.PodcastID} , Total = {show.Total}, Started = {show.Started} Where ID = {show.ID};";
        }
        public async Task<bool> save(PodcastApesode show)
        {
            await initAsync();
            var whereArg = $@"Name = '{ExtraFunctions.reparse_string(show.Name)}' and(PlayUrl = '{show.PlayUrl}' OR Discription = '{ExtraFunctions.reparse_string(show.Discription)}')";
            var cmm = $@"

INSERT INTO PodcastShows (Name,PlayUrl, Published, Discription, Position, Total, Started, PodcastID, ThumbnailIconUrl, PublishedDate )
SELECT '{ExtraFunctions.reparse_string(show.Name)}', '{show.PlayUrl}', '{show.Published.DateTime.ToString()}'
'{show.Published.DateTime.ToString("yyyy-MM-dd HH:mm:ss")}',
'{ExtraFunctions.reparse_string(show.Discription)}'
,{show.Position},{show.Total}, {show.Started}, {show.PodcastID}, '{show.ThumbnailIconUrl}', {show.Published.ToUnixTimeMilliseconds()}
WHERE NOT EXISTS (Select ID from PodcastShows where {whereArg});

UPDATE PodcastShows set name='{ExtraFunctions.reparse_string(show.Name)}', PlayUrl = '{show.PlayUrl}', Published = '{ExtraFunctions.reparseTime(show.Published)}',  
Discription = '{ExtraFunctions.reparse_string(show.Discription)}',
Position = {show.Position},
Total = {show.Total},
Started = {show.Started},
ThumbnailIconUrl = {show.ThumbnailIconUrl}
PublishedDate = {show.Published.ToUnixTimeMilliseconds()}
where {whereArg};
";
            var command = new SqliteCommand(cmm, sqldb);
            await sqldb.OpenAsync();
            return command.ExecuteNonQuery() > 0;
        }
        public async Task<bool> SaveBulck(List<PodcastApesode> shows)
        {
            var stopWatch = new Stopwatch();
            stopWatch.Start();
            await initAsync();
            var commands = "";
            var completed = new List<PodcastApesode>();
            var showsConst = shows.ToImmutableArray();
            var Tasks = new List<Task<string>>();
            var com = 0;
            foreach (var show in showsConst)
            {

                var Ctask = Task.Run(() =>
                {
                    var whereArg = $@"Name = '{ExtraFunctions.reparse_string(show.Name)}' and(PlayUrl = '{show.PlayUrl}' OR Discription = '{ExtraFunctions.reparse_string(show.Discription)}')";
                    var cmm = $@"

INSERT INTO PodcastShows (Name,PlayUrl, Published, Discription, Position, Total, Started, PodcastID, ThumbnailIconUrl, PublishedDate )
SELECT '{ExtraFunctions.reparse_string(show.Name)}', '{show.PlayUrl}', 
'{show.Published.DateTime.ToString("yyyy-MM-dd HH:mm:ss")}',
'{ExtraFunctions.reparse_string(show.Discription)}'
,{show.Position},{show.Total}, {show.Started}, {show.PodcastID}, '{show.ThumbnailIconUrl}', {show.Published.ToUnixTimeMilliseconds()}
WHERE NOT EXISTS (Select ID from PodcastShows where {whereArg});

UPDATE PodcastShows set name='{ExtraFunctions.reparse_string(show.Name)}', PlayUrl = '{show.PlayUrl}', Published = '{ExtraFunctions.reparseTime(show.Published)}',  
Discription = '{ExtraFunctions.reparse_string(show.Discription)}',
Position = {show.Position},
Total = {show.Total},
Started = {show.Started},
ThumbnailIconUrl = '{show.ThumbnailIconUrl}',
PublishedDate = {show.Published.ToUnixTimeMilliseconds()}
where {whereArg};
";
                    com++;
                    return cmm;
                });
                Tasks.Add(Ctask);
            }
            var res = true;
            await Task.WhenAll(Tasks.ToArray());
            var newTasks = new List<Task<bool>>();
            for (int i = 0; i < Tasks.Count(); i++)
            {
                var task = Tasks[i];
                commands += task.Result;
                if (i % 200 == 0)
                {
                    newTasks.Add(sendCommands(commands + "")
                        );
                    commands = "";
                }
            }
            newTasks.Add(sendCommands(commands));
            Task.WaitAll(newTasks.ToArray());
            foreach (var task in newTasks)
            {
                res = res && task.Result;
            }
            stopWatch.Stop();
            return res;

        }
        public async Task<bool> sendCommands(string cmd)
        {
            var command = new SqliteCommand(cmd, sqldb);
            await sqldb.OpenAsync();
            return command.ExecuteNonQuery() > 0;
        }
        public int doesExistStateAddID(PodcastApesode a)
        {
            var Qury = $@"Select ID from PodcastShows where Name = '{ExtraFunctions.reparse_string(a.Name)}' and ( PlayUrl = '{a.PlayUrl}' OR Discription = '{ExtraFunctions.reparse_string(a.Discription)}')";
            sqldb.Open();
            SqliteCommand comd = new SqliteCommand(Qury, sqldb);
            var reader = comd.ExecuteReader();
            var dt = new DataTable();
            dt.Load(reader);
            if (dt.Rows.Count > 0)
            {
                a.ID = int.Parse(dt.Rows[dt.Rows.Count - 1]["ID"].ToString());
                if (!parse_data_row(dt.Rows[dt.Rows.Count - 1]).equals(a))
                {
                    return 0;
                }
                return 1;
            }
            return -1;
        }
        //private async Task<bool> doesNeedUpdate(PodcastApesode a)
        //{
        //    var Qury = $@"Select * from PodcastShows where Name = '{ExtraFunctions.reparse_string(a.Name)}' and ( PlayUrl = '{a.PlayUrl}' OR Discription = '{ExtraFunctions.reparse_string(a.Discription)}')";
        //    await sqldb.OpenAsync();
        //    SqliteCommand comd = new SqliteCommand(Qury, sqldb);
        //    var reader = await comd.ExecuteReaderAsync();
        //    var dt = new DataTable();
        //    dt.Load(reader);
        //    var show = parse_data_row(dt.Rows[dt.Rows.Count - 1]);
        //    return !a.equals(show);
        //}
        public async Task<bool> update(PodcastApesode a)
        {
            await initAsync();

            var Qury = $@"Select * from PodcastShows where Name = '{ExtraFunctions.reparse_string(a.Name)}' and ( PlayUrl = '{a.PlayUrl}' OR Discription = '{ExtraFunctions.reparse_string(a.Discription)}')";
            await sqldb.OpenAsync();
            SqliteCommand comd = new SqliteCommand(Qury, sqldb);
            var reader = await comd.ExecuteReaderAsync();
            var dt = new DataTable();
            dt.Load(reader);
            a.ID = int.Parse(dt.Rows[dt.Rows.Count - 1]["ID"].ToString());
            if (dt.Rows.Count > 0)
            {
                var cmd = $@"update PodcastShows set Name = '{ExtraFunctions.reparse_string(a.Name)}', PlayUrl= '{a.PlayUrl}', Published = '{a.Published.DateTime.ToString("yyyy-MM-dd HH:mm:ss")}' , Discription = '{ExtraFunctions.reparse_string(a.Discription)}', Position = {a.Position} , PodcastID = {a.PodcastID} Where ID = {a.ID}";
                sqldb.Open();
                SqliteCommand insert_comd = new SqliteCommand(cmd, sqldb);

                return await insert_comd.ExecuteNonQueryAsync() > 0;
            }
            return false;
        }
        public async Task<bool> delete(PodcastApesode show)
        {
            await initAsync();
            var Qury =
    $@"Delete * from PodcastShows where ID = '{show.ID}'";
            SqliteCommand comd = new SqliteCommand(Qury, sqldb);
            return await comd.ExecuteNonQueryAsync() > 0;
        }
        public async Task<ObservableCollection<PodcastApesode>> get_all_shows(int limit)
        {
            await initAsync();
            var Qury =
    $@"Select * from PodcastShows ORDER by Published DESC LIMIT {limit};";
            SqliteCommand comd = new SqliteCommand(Qury, sqldb);
            sqldb.Open();
            var reader = await comd.ExecuteReaderAsync();
            var dt = new DataTable();
            dt.Load(reader);
            var PodcastShows = new ObservableCollection<PodcastApesode>();
            foreach (DataRow row in dt.Rows)
            {
                PodcastShows.Add(parse_data_row(row));
            }
            return PodcastShows;
        }
        public async Task<ObservableCollection<PodcastApesode>> get_all_shows(int limit, int start)
        {
            await initAsync();
            var Qury =
    $@"Select * from PodcastShows ORDER by PublishedDate DESC LIMIT {limit} OFFSET {start};";
            SqliteCommand comd = new SqliteCommand(Qury, sqldb);
            sqldb.Open();
            var reader = await comd.ExecuteReaderAsync();
            var dt = new DataTable();
            dt.Load(reader);
            var PodcastShows = new ObservableCollection<PodcastApesode>();
            foreach (DataRow row in dt.Rows)
            {
                PodcastShows.Add(parse_data_row(row));
            }
            return PodcastShows;
        }
        private PodcastApesode parse_data_row(DataRow row)
        {
            var show = new PodcastApesode();
            show.ID = int.Parse(row["ID"].ToString());
            show.PodcastID = int.Parse(row["PodcastID"].ToString());
            show.Name = row["Name"].ToString();
            show.PlayUrl = row["PlayUrl"].ToString();
            show.Published = DateTimeOffset.Parse(row["Published"].ToString());
            show.Discription = row["Discription"].ToString();
            show.Position = int.Parse(row["Position"].ToString());
            show.Total = int.Parse(row["Total"].ToString());
            show.Started = int.Parse(row["Started"].ToString());
            show.ThumbnailIconUrl = row["ThumbnailIconUrl"].ToString();

            return show;
        }
        private PodcastApesode parse_data_row(DataRow row, Podcast pod)
        {
            var show = new PodcastApesode();
            show.ID = int.Parse(row["ID"].ToString());
            show.PodcastID = int.Parse(row["PodcastID"].ToString());
            show.Name = row["Name"].ToString();
            show.PlayUrl = row["PlayUrl"].ToString();
            show.Published = DateTimeOffset.Parse(row["Published"].ToString());
            show.Discription = row["Discription"].ToString();
            show.Position = int.Parse(row["Position"].ToString());
            show.Total = int.Parse(row["Total"].ToString());
            show.Started = int.Parse(row["Started"].ToString());
            show.ThumbnailIconUrl = row["ThumbnailIconUrl"].ToString();
            show.PodcastRss = pod.Rss_url;
            return show;
        }
        public async Task<ObservableCollection<PodcastApesode>> get_all_shows_for_Podcast(Podcast podcast)
        {
            await initAsync();
            var Qury =
    $@"Select * from PodcastShows where PodcastID ={podcast.ID} ORDER by Published DESC;";
            SqliteCommand comd = new SqliteCommand(Qury, sqldb);
            sqldb.Open();
            var reader = comd.ExecuteReader();
            var dt = new DataTable();
            dt.Load(reader);
            var PodcastShows = new ObservableCollection<PodcastApesode>();
            foreach (DataRow row in dt.Rows)
            {
                PodcastShows.Add(parse_data_row(row, podcast));
            }
            return PodcastShows;
        }
        public async Task<ObservableCollection<PodcastApesode>> get_all_shows_for_Podcast(Podcast podcast, int limit)
        {
            await initAsync();
            var Qury =
    $@"Select * from PodcastShows where PodcastID ={podcast.ID} ORDER by Published DESC LIMIT {limit};";
            SqliteCommand comd = new SqliteCommand(Qury, sqldb);
            sqldb.Open();
            var reader = comd.ExecuteReader();
            var dt = new DataTable();
            dt.Load(reader);
            var PodcastShows = new ObservableCollection<PodcastApesode>();
            foreach (DataRow row in dt.Rows)
            {
                PodcastShows.Add(parse_data_row(row, podcast));
            }
            return PodcastShows;
        }
        public async Task<ObservableCollection<PodcastApesode>> get_all_shows_for_Podcast(Podcast podcast, int limit, int start)
        {
            await initAsync();
            var Qury =
    $@"Select * from PodcastShows where PodcastID ={podcast.ID} ORDER by Published DESC LIMIT {limit} OFFSET {start};";
            SqliteCommand comd = new SqliteCommand(Qury, sqldb);
            sqldb.Open();
            var reader = comd.ExecuteReader();
            var dt = new DataTable();
            dt.Load(reader);
            var PodcastShows = new ObservableCollection<PodcastApesode>();
            foreach (DataRow row in dt.Rows)
            {
                PodcastShows.Add(parse_data_row(row, podcast));
            }
            return PodcastShows;
        }


    }
}
