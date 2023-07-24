﻿using Microsoft.Data.Sqlite;
using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Data;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Windows.Storage;

namespace PodMerForWinUi.Sql.SqlLite
{
    public class SqlLitePodcasts
    {
        public SqliteConnection sqldb;

        public SqlLitePodcasts()
        {
        }

        public async Task init()
        {
            await ApplicationData.Current.LocalFolder.CreateFileAsync("sqliteSample.db", CreationCollisionOption.OpenIfExists);
            string dbpath = Path.Combine(ApplicationData.Current.LocalFolder.Path,
                                         "sqliteSample.db");
            var db = new Microsoft.Data.Sqlite.SqliteConnection($"Filename={dbpath}");
            db.Open();

                string tableCommand = "CREATE TABLE IF NOT " +
                    @"EXISTS Podcasts (	[ID] INTEGER PRIMARY KEY AUTOINCREMENT ,
    [Name][nvarchar](8000) NULL,
	[RssUrl][nvarchar](8000) NULL,
    [ImageUrl][nvarchar](8000) NULL);

";
                var createTable = new SqliteCommand(tableCommand, db);
                createTable.ExecuteReader();

                sqldb = db;
        }
        public async Task<int> add(Podcast a)
        {
            await init();
            try
            {
                if(a == null)
                {
                    throw new Exception();
                }

                var Qury =
                    $@"Select * from Podcasts where Name = '{a.Name.Replace("'", "''")}' and ( RssUrl = '{a.Rss_url}' OR ImageUrl = '{a.ImageUrl}')";
                SqliteCommand comd = new SqliteCommand(Qury, sqldb);
                sqldb.Open();
                var reader = await comd.ExecuteReaderAsync();
                var dt = new DataTable();
                dt.Load(reader);

                if (dt.Rows.Count <= 0)
                {
                    var cmd = $@"Insert into Podcasts (Name, RssUrl, ImageUrl) VALUES ('{ExtraFunctions.reparse_string(a.Name)}', '{a.Rss_url}', '{a.ImageUrl}')";
                    sqldb.Open();
                    SqliteCommand insert_comd = new SqliteCommand(cmd, sqldb);
                    if (await insert_comd.ExecuteNonQueryAsync() > 0)
                    {
                        Qury = $@"Select * from Podcasts where Name = '{ExtraFunctions.reparse_string(a.Name)}' and  RssUrl = '{a.Rss_url}' and ImageUrl = '{a.ImageUrl}'";
                        comd = new SqliteCommand(Qury, sqldb);
                        sqldb.Open();
                        reader = await comd.ExecuteReaderAsync();
                        dt = new DataTable();
                        dt.Load(reader);
                        return int.Parse(dt.Rows[dt.Rows.Count - 1]["ID"].ToString());
                    }
                }
                throw new Exception("podcast already exists");
            }
            catch
            {
                throw new Exception("adding podcasts has caused an error");
            }
        }
        public async Task<bool> update(Podcast a)
        {
            await init();

            var Qury =
                $@"Select * from Podcasts where Name = '{ExtraFunctions.reparse_string(a.Name)}' OR RssUrl = '{a.Rss_url}' OR ImageUrl = '{a.ImageUrl}'";
            await sqldb.OpenAsync();
            SqliteCommand comd = new SqliteCommand(Qury, sqldb);
            var reader = await comd.ExecuteReaderAsync();
            var dt = new DataTable();
            dt.Load(reader);
            a.ID = int.Parse(dt.Rows[dt.Rows.Count - 1]["ID"].ToString());
            if (dt.Rows.Count > 0)
            {
                var cmd = $@"update Podcasts set Name = '{ExtraFunctions.reparse_string(a.Name)}', RssUrl= '{a.Rss_url}', ImageUrl = '{a.ImageUrl}' Where ID = {a.ID}";
                sqldb.Open();
                SqliteCommand insert_comd = new SqliteCommand(cmd, sqldb);
                exequ:
                try
                {
                    return await insert_comd.ExecuteNonQueryAsync() > 0;

                }
                catch(Exception e)
                {
                    if(e.Message.Equals(@"SQLite Error 5: 'database is locked'."))
                    {
                        Task.Delay(((int)(new Random()).NextDouble() * 100));
                        goto exequ;
                    }
                }
            }
            return false;
        }
        public async Task<bool> delete(Podcast podcast)
        {
            await init();
            var Qury =
    $@"Delete * from Podcasts where ID = '{podcast.ID}'";
            SqliteCommand comd = new SqliteCommand(Qury, sqldb);
            return await comd.ExecuteNonQueryAsync() > 0;
        }
        public async Task<ObservableCollection<Podcast>> get_all_podcasts()
        {
            await init();
            var Qury =
    $@"Select * from Podcasts;";
            SqliteCommand comd = new SqliteCommand(Qury, sqldb);
            sqldb.Open();
            var reader = await comd.ExecuteReaderAsync();
            var dt = new DataTable();
            dt.Load(reader);
            var Podcasts = new ObservableCollection<Podcast>();
            foreach (DataRow row in dt.Rows)
            {
                var podcast = new Podcast();
                podcast.ID = int.Parse(row["ID"].ToString());
                podcast.ImageUrl = row["ImageUrl"].ToString();
                podcast.Name = row["Name"].ToString();
                podcast.Rss_url = row["RssUrl"].ToString();
                Podcasts.Add(podcast);
            }
            return Podcasts;
        }
        public async Task<bool> DeepDeleteByRssFeed(string rssFeedUrl)
        {
            await init();
            sqldb.Open();
            var Qury =
    $@"delete from PodcastShows where PodcastId = 
(select ID from Podcasts where RssUrl = '{rssFeedUrl}' Limit 1);
delete from Podcasts where RssUrl = '{rssFeedUrl}';
";
            SqliteCommand comd = new SqliteCommand(Qury, sqldb);
            return await comd.ExecuteNonQueryAsync() > 0;
        }
        public async Task saveToDbAllShowsAndPodcasts(ObservableCollection<Podcast> Pods_new, ObservableCollection<Podcast> Pods_old)
        {
            Func<PodcastApesode, PodcastApesode, bool> isSameShow = (show, Show) => {
                var equals = new bool[6];
                equals[0] = show.PlayUrl.Equals(Show.PlayUrl);
                equals[1] = show.Total == Show.Total;
                equals[2] = show.Discription.Equals(Show.Discription);
                equals[3] = show.Name.Equals(Show.Name);
                equals[4] = show.Published.Equals(Show.Published);
                equals[5] = show.PodcastID == Show.PodcastID;
                int conds = 0;
                for (int i = 0; i < equals.Count(); i++)
                {
                    if (equals[i])
                    {
                        conds++;
                    }
                }
                return conds >= 4;
            };
            var ShowList = new List<PodcastApesode>();
            foreach (var pod in Pods_new)
            {
                try
                {
                    pod.ID = await add(pod);
                }
                catch
                {
                    await update(pod);
                }

                var oldPod = Pods_old.Where((podcast) =>
                {
                    return podcast.Name.Equals(pod.Name);
                }).FirstOrDefault();
                foreach (var show in pod.PodcastApesodes)
                {
                    show.PodcastID = pod.ID;
                    if (oldPod != null)
                    {
                        var oldShow = oldPod.PodcastApesodes.Where((Show) => isSameShow(show, Show)).FirstOrDefault();
                        double conditoions = 0;
                        if (oldShow != null)
                        {
                            bool[] equalsss = new bool[7] {
                            oldShow.PlayUrl.Equals(show.PlayUrl),
                            oldShow.Total == show.Total,
                             oldShow.Discription.Equals(show.Discription),
                            oldShow.Name.Equals(show.Name),
                            oldShow.Published.Equals(show.Published),
                            oldShow.PodcastID == show.PodcastID,
                            oldShow.ThumbnailIconUrl.Equals(show.ThumbnailIconUrl) };
                            conditoions = 0;
                            for (int i = 0; i < equalsss.Count(); i++)
                            {
                                if (equalsss[i])
                                {
                                    conditoions++;
                                }
                            }
                            if (conditoions != equalsss.Length)
                            {
                                show.Position = oldShow.Position;
                                ShowList.Add(show);
                            }

                        }
                        else
                        {
                            ShowList.Add(show);
                        }

                    }


                    else
                    {
                        ShowList.Add(show);
                    }
                }
            }

            try
            {
                var showsDb = new SqlLitePodcastsShows();
                await showsDb.initAsync();
                var result = await showsDb.SaveBulck(ShowList);
            }
            catch
            {

            }
        }


    }
}
