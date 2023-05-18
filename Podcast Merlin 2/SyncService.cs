using Microsoft.Data.Sqlite;
using Newtonsoft.Json;
using PodMerForWinUi.Sql.SqlLite;
using System;
using System.Collections.Generic;
using System.IO;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text;
using System.Threading.Tasks;
using static PodMerForWinUi.MainPage;

namespace PodMerForWinUi.Sync
{
    public class SyncService
    {
        private static Sql.SqlLite.SqlLitePodcastsShows ShowsDb = new Sql.SqlLite.SqlLitePodcastsShows();
        private static Sql.SqlLite.SqlLitePodcasts PodsDb = new Sql.SqlLite.SqlLitePodcasts();

        public static Windows.Storage.ApplicationDataContainer localSettings =
Windows.Storage.ApplicationData.Current.LocalSettings;
        public static Windows.Storage.StorageFolder localFolder =
            Windows.Storage.ApplicationData.Current.LocalFolder;
        public static HttpClient client_for_nextcloud = new HttpClient();
        public static SqlLiteActions ActionsDb = new SqlLiteActions();
        public static loginPageDitales Server_Details = MainPage.Server_Details;
        public static async Task<bool> is_connected_to_users_server()
        {
            client_for_nextcloud.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Basic", Convert.ToBase64String(Encoding.ASCII.GetBytes($"{MainPage.Server_Details.login_name}:{MainPage.Server_Details.app_password}")));
            try
            {
                var res = await client_for_nextcloud.GetAsync(Server_Details.server + $"/index.php/apps/gpoddersync/subscriptions?since={int.MaxValue}");
                return res.IsSuccessStatusCode;

            }
            catch
            {
                return false;
            }

        }
        public static async Task<ActionsResponse> get_actions_and_put_them_on_file()
        {
            await ActionsDb.init();
            ActionsResponse all;
            string res;
            if (await is_connected_to_users_server())
            {
                client_for_nextcloud.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Basic", Convert.ToBase64String(Encoding.ASCII.GetBytes($"{MainPage.Server_Details.login_name}:{MainPage.Server_Details.app_password}")));
                if (localSettings.Values["last_checked_actions_timestamp"] == null)
                {
                    res = await client_for_nextcloud.GetStringAsync(Server_Details.server + "/index.php/apps/gpoddersync/episode_action");

                }
                else
                {
                    res = await client_for_nextcloud.GetStringAsync(Server_Details.server + $"/index.php/apps/gpoddersync/episode_action?since={int.Parse(localSettings.Values["last_checked_actions_timestamp"].ToString())}");
                }
                var ser = new Newtonsoft.Json.JsonSerializer();
                all = Newtonsoft.Json.JsonConvert.DeserializeObject(res, typeof(ActionsResponse)) as ActionsResponse;
                foreach (var action in all.actions)
                {
                    await ActionsDb.add(action);
                }
                localSettings.Values["last_checked_actions_timestamp"] = all.timestamp;
                await ShowsDb.initAsync();
                string NoneQury = "";
                foreach (var action in all.actions)
                {
                    NoneQury += $@" Update PodcastShows set position = {action.position} where PlayUrl = '{action.episode}' ;";

                }
                ShowsDb.sqldb.Open();
                var cmd = new SqliteCommand(NoneQury, ShowsDb.sqldb);
                try
                {
                    var result = cmd.ExecuteNonQuery();
                }
                catch
                {

                }
            }
            return new ActionsResponse() { timestamp = int.Parse(localSettings.Values["last_checked_actions_timestamp"].ToString()), actions = await ActionsDb.get_all_actions() };

        }
        public static async Task SyncCashedActions()
        {
            await ShowsDb.initAsync();
            await ActionsDb.init();
            string NoneQury = "";
            var actions = await ActionsDb.get_all_actions();
            foreach (var action in actions)
            {
                NoneQury += $@" Update PodcastShows set position = {action.position} where PlayUrl = '{action.episode}' ;";

            }
            ShowsDb.sqldb.Open();
            var cmd = new SqliteCommand(NoneQury, ShowsDb.sqldb);
            try
            {
                var result = cmd.ExecuteNonQuery();
            }
            catch
            {

            }
        }
        public static async Task<bool> SendEnqueuedActions()
        {
            client_for_nextcloud.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Basic", Convert.ToBase64String(Encoding.ASCII.GetBytes($"{Server_Details.login_name}:{Server_Details.app_password}")));
            Windows.Storage.StorageFolder folder = Windows.Storage.ApplicationData.Current.LocalFolder;
            Windows.Storage.StorageFile file = await folder.GetFileAsync("actions_to_send.json");
            string actionsToSend = await Windows.Storage.FileIO.ReadTextAsync(file);
            StringReader reader = new StringReader(actionsToSend);
            Newtonsoft.Json.JsonSerializer jsonSerializerr = new Newtonsoft.Json.JsonSerializer();
            var ls = jsonSerializerr.Deserialize(reader, typeof(List<Dictionary<string, object>>)) as List<Dictionary<string, object>>;
            var isSucsesfull = true;
            var requstContent = System.Net.Http.Json.JsonContent.Create(ls, typeof(List<Dictionary<string, object>>));
            var res = await client_for_nextcloud.PostAsync(new System.Uri(MainPage.Server_Details.server + "/index.php/apps/gpoddersync/episode_action/create"), requstContent);
            isSucsesfull = isSucsesfull && res.IsSuccessStatusCode;
            if (isSucsesfull)
            {
                localSettings.Values["is_there_actions_to_send"] = false.ToString();
                Windows.Storage.StorageFolder storageFolder = Windows.Storage.ApplicationData.Current.LocalFolder;
                Windows.Storage.StorageFile sampleFile = await storageFolder.CreateFileAsync("actions_to_send.json", Windows.Storage.CreationCollisionOption.ReplaceExisting);
                requstContent = System.Net.Http.Json.JsonContent.Create(new List<Dictionary<string, object>>(), typeof(List<Dictionary<string, object>>));
                await Windows.Storage.FileIO.WriteTextAsync(sampleFile, await requstContent.ReadAsStringAsync());
            }

            return isSucsesfull;
        }
        public static async Task<bool> SendAction(ShowAndPodcast showAndPodcast, int position)
        {
            client_for_nextcloud.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Basic", Convert.ToBase64String(Encoding.ASCII.GetBytes($"{MainPage.Server_Details.login_name}:{MainPage.Server_Details.app_password}")));
            Task.Run(async () =>
            {
                await ShowsDb.update(showAndPodcast.Show);
            }).Wait();
            var show = showAndPodcast.Show;
            var podcast = showAndPodcast.Podcast;
            var dateFormat = "yyyy-MM-ddTHH:mm:ss";
            var dictrequst = new Dictionary<string, object>
            {
                { "podcast", podcast.Rss_url },
                { "episode", show.PlayUrl },
                { "guid", show.Id },
                { "action", "play" },
                { "started", show.Started },
                { "total", show.Total },
                { "timestamp", DateTime.Now.ToUniversalTime().ToString(dateFormat) },
                { "position", position }
            };
            if (show.Id == null || show.Id == "")
            {
                dictrequst.Remove("guid");
            }
            var ls = new List<Dictionary<string, object>>
            {
                dictrequst
            };
            var requstContent = System.Net.Http.Json.JsonContent.Create(ls, typeof(List<Dictionary<string, object>>));
            var task = is_connected_to_users_server();
            task.Wait(4000);
            bool isCon = false;
            if (!task.IsCompleted)
            {
                isCon = false;
            }
            else
            {
                isCon = task.Result;
            }
            if (isCon)
            {
                try
                {
                    var ts = client_for_nextcloud.PostAsync(new System.Uri(MainPage.Server_Details.server + "/index.php/apps/gpoddersync/episode_action/create"), requstContent);
                    ts.Wait();
                    var res = ts.Result;
                    var ts1 = Task.Run(async () => await get_actions_and_put_them_on_file());
                    ts1.Wait();
                    return res.IsSuccessStatusCode;
                }
                catch
                {
                    return false;
                }
            }
            else
            {
                if (localSettings.Values["is_there_actions_to_send"] == null || localSettings.Values["is_there_actions_to_send"].ToString().Equals(false.ToString()))
                {
                    Windows.Storage.StorageFolder storageFolder = Windows.Storage.ApplicationData.Current.LocalFolder;
                    var ts = storageFolder.CreateFileAsync("actions_to_send.json", Windows.Storage.CreationCollisionOption.ReplaceExisting);
                    ts.AsTask().Wait();
                    Windows.Storage.StorageFile sampleFile = ts.GetResults();
                    var q = new List<Dictionary<string, object>>();
                    q.Add(dictrequst);
                    requstContent = System.Net.Http.Json.JsonContent.Create(q, typeof(List<Dictionary<string, object>>));
                    var ts1 = Windows.Storage.FileIO.WriteTextAsync(sampleFile, await requstContent.ReadAsStringAsync());
                    ts.AsTask().Wait();
                }
                else
                {
                    var ts = Task.Run(async () =>
                    {
                        Windows.Storage.StorageFolder folder = Windows.Storage.ApplicationData.Current.LocalFolder;
                        Windows.Storage.StorageFile file = await folder.GetFileAsync("actions_to_send.json");
                        string actionsToSend = await Windows.Storage.FileIO.ReadTextAsync(file);
                        StringReader reader = new StringReader(actionsToSend);
                        Newtonsoft.Json.JsonSerializer jsonSerializerr = new Newtonsoft.Json.JsonSerializer();
                        var queue = jsonSerializerr.Deserialize(reader, typeof(List<Dictionary<string, object>>)) as List<Dictionary<string, object>>;
                        queue.Add(dictrequst);
                        Windows.Storage.StorageFolder storageFolder = Windows.Storage.ApplicationData.Current.LocalFolder;
                        Windows.Storage.StorageFile sampleFile = await storageFolder.CreateFileAsync("actions_to_send.json", Windows.Storage.CreationCollisionOption.ReplaceExisting);
                        requstContent = System.Net.Http.Json.JsonContent.Create(queue, typeof(List<Dictionary<string, object>>));
                        await Windows.Storage.FileIO.WriteTextAsync(sampleFile, await requstContent.ReadAsStringAsync());
                    });
                    ts.Wait();

                }
                localSettings.Values["is_there_actions_to_send"] = true.ToString();
                return false;

            }


        }
        public static async Task<List<string>> get_podcasts_urls()
        {
            var client = new HttpClient();
            var credentials = new AuthenticationHeaderValue("Basic", Convert.ToBase64String(Encoding.ASCII.GetBytes($"{Server_Details.login_name}:{Server_Details.app_password}")));
            client.DefaultRequestHeaders.Authorization = credentials;


            List<string> podcasts_from_file;
            string pods;
            if (await is_connected_to_users_server())
            {
                if (localSettings.Values["last_checked_podcasts_urls_timestamp"] == null)
                {
                    podcasts_from_file = new List<string>();
                    pods = await client.GetStringAsync(Server_Details.server + "/index.php/apps/gpoddersync/subscriptions");
                }
                else
                {
                    Windows.Storage.StorageFolder folder = Windows.Storage.ApplicationData.Current.LocalFolder;
                    Windows.Storage.StorageFile file = await folder.GetFileAsync("podcasts_url.json");
                    string podcasts_sirielized = await Windows.Storage.FileIO.ReadTextAsync(file);
                    StringReader reader = new StringReader(podcasts_sirielized);
                    Newtonsoft.Json.JsonSerializer jsonSerializerr = new Newtonsoft.Json.JsonSerializer();
                    podcasts_from_file = jsonSerializerr.Deserialize(reader, typeof(List<string>)) as List<string>;

                    pods = await client.GetStringAsync(Server_Details.server + $"/index.php/apps/gpoddersync/subscriptions" +
                        $"?since={long.Parse(localSettings.Values["last_checked_podcasts_urls_timestamp"].ToString())}");
                }
                Newtonsoft.Json.JsonSerializer jsonSerializer = new Newtonsoft.Json.JsonSerializer();
                var st = new StringReader(pods);
                SubscriptionsResponse res_disirialized = jsonSerializer.Deserialize(st, typeof(SubscriptionsResponse)) as SubscriptionsResponse;
                List<string> podcasts = podcasts_from_file;
                foreach (string podcast in res_disirialized.add)
                {
                    if (!podcasts.Contains(podcast))
                    {
                        podcasts.Add(podcast);
                    }
                }
                foreach (string podcast in res_disirialized.remove)
                {
                    await PodsDb.DeepDeleteByRssFeed(podcast);
                    podcasts.RemoveAll((str) => str.Equals(podcast));
                }
                var textWriter = new StringWriter();
                Newtonsoft.Json.JsonSerializer jsonSerializer1 = new Newtonsoft.Json.JsonSerializer()
                {
                    Formatting = Newtonsoft.Json.Formatting.Indented,

                };
                jsonSerializer1.Serialize(textWriter, podcasts);
                Windows.Storage.StorageFolder storageFolder = Windows.Storage.ApplicationData.Current.LocalFolder;
                Windows.Storage.StorageFile sampleFile = await storageFolder.CreateFileAsync("podcasts_url.json", Windows.Storage.CreationCollisionOption.ReplaceExisting);
                await Windows.Storage.FileIO.WriteTextAsync(sampleFile, textWriter.ToString());
                localSettings.Values["last_checked_podcasts_urls_timestamp"] = res_disirialized.timestamp.ToString();
                return podcasts;
            }
            else
            {
                Windows.Storage.StorageFolder folder = Windows.Storage.ApplicationData.Current.LocalFolder;
                Windows.Storage.StorageFile file = await folder.GetFileAsync("podcasts_url.json");
                string podcasts_sirielized = await Windows.Storage.FileIO.ReadTextAsync(file);
                StringReader reader = new StringReader(podcasts_sirielized);
                Newtonsoft.Json.JsonSerializer jsonSerializerr = new Newtonsoft.Json.JsonSerializer();
                podcasts_from_file = jsonSerializerr.Deserialize(reader, typeof(List<string>)) as List<string>;
                return podcasts_from_file;
            }

        }
        private static Dictionary<string, List<string>> add_action_to_dict(Dictionary<string, List<string>> dict, string rssUrl, string actionType)
        {
            if (!dict.ContainsKey("add") || dict["add"] == null)
            {
                dict["add"] = new List<string>();
            }
            if (!dict.ContainsKey("remove") || dict["remove"] == null)
            {
                dict["remove"] = new List<string>();
            }
            if (actionType.Equals("add"))
            {
                dict["add"].Add(rssUrl);
            }
            else
            {
                dict["remove"].Add(rssUrl);
            }
            return dict;

        }
        public static async Task<bool> sendPendingSubs()
        {
            client_for_nextcloud.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Basic", Convert.ToBase64String(Encoding.ASCII.GetBytes($"{Server_Details.login_name}:{Server_Details.app_password}")));
            Windows.Storage.StorageFolder folder = Windows.Storage.ApplicationData.Current.LocalFolder;
            Windows.Storage.StorageFile file = await folder.GetFileAsync("subscriptions_to_send.json");
            string SubsToSend = await Windows.Storage.FileIO.ReadTextAsync(file);
            StringReader reader = new StringReader(SubsToSend);
            Newtonsoft.Json.JsonSerializer jsonSerializerr = new Newtonsoft.Json.JsonSerializer();
            var ls = jsonSerializerr.Deserialize(reader, typeof(Dictionary<string, List<string>>)) as Dictionary<string, List<string>>;
            var isSucsesfull = true;
            var requstContent = System.Net.Http.Json.JsonContent.Create(ls, typeof(Dictionary<string, List<string>>));
            var res = await client_for_nextcloud.PostAsync(new System.Uri(MainPage.Server_Details.server + "/index.php/apps/gpoddersync/subscription_change/create"), requstContent);
            isSucsesfull = isSucsesfull && res.IsSuccessStatusCode;
            if (isSucsesfull)
            {
                localSettings.Values["are_there_subscription_changes_to_send"] = false.ToString();
                Windows.Storage.StorageFolder storageFolder = Windows.Storage.ApplicationData.Current.LocalFolder;
                Windows.Storage.StorageFile sampleFile = await storageFolder.CreateFileAsync("subscriptions_to_send.json", Windows.Storage.CreationCollisionOption.ReplaceExisting);
                requstContent = System.Net.Http.Json.JsonContent.Create(new Dictionary<string, List<string>>(), typeof(Dictionary<string, List<string>>));
                await Windows.Storage.FileIO.WriteTextAsync(sampleFile, await requstContent.ReadAsStringAsync());
            }

            return isSucsesfull;
        }
        public static async Task<bool> add_or_remove_podcast(string rssUrl, string actionType)
        {
            client_for_nextcloud.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Basic", Convert.ToBase64String(Encoding.ASCII.GetBytes($"{MainPage.Server_Details.login_name}:{MainPage.Server_Details.app_password}")));
            var ls = new List<string>();
            ls.Add(rssUrl);


            try
            {
                if (await is_connected_to_users_server())
                {

                    //Newtonsoft.Json.JsonSerializer jsonSerializer1 = new Newtonsoft.Json.JsonSerializer()
                    //{
                    //    Formatting = Newtonsoft.Json.Formatting.Indented,

                    //};
                    //var textWriter = new StringWriter();
                    //jsonSerializer1.Serialize(textWriter, content);
                    //var str = textWriter.ToString();
                    Dictionary<string, List<string>> content = new Dictionary<string, List<string>>();
                    content = add_action_to_dict(content, rssUrl, actionType);
                    var res = await client_for_nextcloud.PostAsync(new System.Uri(MainPage.Server_Details.server + "/index.php/apps/gpoddersync/subscription_change/create"), JsonContent.Create(content, typeof(Dictionary<string, List<string>>)));



                    await addOrDeleteFromFileAndDb(rssUrl, actionType);
                    await get_actions_and_put_them_on_file();
                    return res.IsSuccessStatusCode;
                }
                else
                {
                    var are_there_subscription_changes_to_send = localSettings.Values["are_there_subscription_changes_to_send"];
                    if (are_there_subscription_changes_to_send == null || !bool.Parse(are_there_subscription_changes_to_send.ToString()))
                    {
                        Dictionary<string, List<string>> content = new Dictionary<string, List<string>>();
                        content = add_action_to_dict(content, rssUrl, actionType);
                        Windows.Storage.StorageFolder storageFolder = Windows.Storage.ApplicationData.Current.LocalFolder;
                        Windows.Storage.StorageFile sampleFile = await storageFolder.CreateFileAsync("subscriptions_to_send.json", Windows.Storage.CreationCollisionOption.ReplaceExisting);
                        var requstContent = System.Net.Http.Json.JsonContent.Create(content, typeof(Dictionary<string, List<string>>));
                        await Windows.Storage.FileIO.WriteTextAsync(sampleFile, await requstContent.ReadAsStringAsync());
                    }
                    else
                    {
                        Windows.Storage.StorageFolder folder = Windows.Storage.ApplicationData.Current.LocalFolder;
                        Windows.Storage.StorageFile file = await folder.GetFileAsync("subscriptions_to_send.json");
                        string podcasts_sirielized = await Windows.Storage.FileIO.ReadTextAsync(file);
                        StringReader reader = new StringReader(podcasts_sirielized);
                        Newtonsoft.Json.JsonSerializer jsonSerializerr = new Newtonsoft.Json.JsonSerializer();
                        var content = jsonSerializerr.Deserialize(reader, typeof(Dictionary<string, List<string>>)) as Dictionary<string, List<string>>;

                        content = add_action_to_dict(content, rssUrl, actionType);
                        Windows.Storage.StorageFolder storageFolder = Windows.Storage.ApplicationData.Current.LocalFolder;
                        Windows.Storage.StorageFile sampleFile = await storageFolder.CreateFileAsync("subscriptions_to_send.json", Windows.Storage.CreationCollisionOption.ReplaceExisting);
                        var requstContent = System.Net.Http.Json.JsonContent.Create(content, typeof(Dictionary<string, List<string>>));
                        await Windows.Storage.FileIO.WriteTextAsync(sampleFile, await requstContent.ReadAsStringAsync());
                    }
                    await addOrDeleteFromFileAndDb(rssUrl, actionType);
                    localSettings.Values["are_there_subscription_changes_to_send"] = true.ToString();
                    return true;
                }

            }
            catch
            {
                return false;
            }

        }
        private async static Task addOrDeleteFromFileAndDb(string rssUrl, string actionType)
        {
            Windows.Storage.StorageFolder folder1 = Windows.Storage.ApplicationData.Current.LocalFolder;
            Windows.Storage.StorageFile file1 = await folder1.GetFileAsync("podcasts_url.json");
            string podcasts_sirielized1 = await Windows.Storage.FileIO.ReadTextAsync(file1);
            StringReader reader1 = new StringReader(podcasts_sirielized1);
            Newtonsoft.Json.JsonSerializer jsonSerializerr1 = new Newtonsoft.Json.JsonSerializer();
            var podcasts_from_file = jsonSerializerr1.Deserialize(reader1, typeof(List<string>)) as List<string>;
            if (actionType.Equals("add"))
            {

                podcasts_from_file.Add(rssUrl);
            }
            else
            {
                podcasts_from_file.Remove(rssUrl);
                await PodsDb.DeepDeleteByRssFeed(rssUrl);
            }
            var textWriter = new StringWriter();
            Newtonsoft.Json.JsonSerializer jsonSerializer1 = new Newtonsoft.Json.JsonSerializer()
            {
                Formatting = Newtonsoft.Json.Formatting.Indented,

            };
            jsonSerializer1.Serialize(textWriter, podcasts_from_file);
            Windows.Storage.StorageFolder storageFolder1 = Windows.Storage.ApplicationData.Current.LocalFolder;
            Windows.Storage.StorageFile sampleFile1 = await storageFolder1.CreateFileAsync("podcasts_url.json", Windows.Storage.CreationCollisionOption.ReplaceExisting);
            await Windows.Storage.FileIO.WriteTextAsync(sampleFile1, textWriter.ToString());
        }
        public class SubscriptionsRequst
        {
            [JsonProperty("add")]

            public List<string> add;
            [JsonProperty("remove")]

            public List<string> remove;
        }


        public class SubscriptionsResponse
        {
            public List<string> add;
            public List<string> remove;
            public long timestamp;
        }

    }
}
