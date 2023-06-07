using Newtonsoft.Json;
using System;
using System.Collections.ObjectModel;
using System.Linq;
using System.Net.Http;
using System.Threading.Tasks;

namespace PodMerForWinUi
{
    public class Podcast
    {
        public Podcast() { }
        private string imageUrl = "";
        private string name = "";
        private string rss_url = "";
        private string rss_feed = "";
        private int iD = 0;
        private ObservableCollection<PodcastApesode> podcastApesodes = new ObservableCollection<PodcastApesode>();
        public string ImageUrl { get => imageUrl; set => imageUrl = value; }
        public string Name { get => name; set => name = value; }
        public string Rss_url { get => rss_url; set => rss_url = value; }
        //public string Rss_feed { get => rss_feed; set => rss_feed = value; }
        [JsonProperty("PodcastApesodes")]
        public ObservableCollection<PodcastApesode> PodcastApesodes { get => podcastApesodes; set => podcastApesodes = value; }
        //public string Rss_id { get => rss_id; set => rss_id = value; }
        public int ID { get => iD; set => iD = value; }
        public static async Task<Podcast> get_podcast_from_url_string(string url)
        {

            var pod = new Podcast() { Rss_url = url };
            var Client = new HttpClient();
            try
            {
                Windows.Web.Syndication.SyndicationClient client = new Windows.Web.Syndication.SyndicationClient();
                Windows.Web.Syndication.SyndicationFeed feedy;
                // The URI is validated by catching exceptions thrown by the Uri constructor.
                System.Uri uri = null;
                // Use your own uriString for the feed you are connecting to.
                try
                {
                    uri = new System.Uri(url);
                }
                catch { }
                client.SetRequestHeader("User-Agent", "Mozilla/5.0 (compatible; MSIE 10.0; Windows NT 6.2; WOW64; Trident/6.0)");


                feedy = await client.RetrieveFeedAsync(uri);

                foreach (var atr in feedy.ElementExtensions)
                {
                    try
                    {
                        switch (atr.NodeName)
                        {
                            case "image":
                                if (atr.NodeNamespace.Equals("http://www.itunes.com/dtds/podcast-1.0.dtd"))
                                {
                                    pod.ImageUrl = atr.AttributeExtensions[0].Value;
                                }
                                else
                                {
                                    if (pod.ImageUrl == "" || pod.ImageUrl == null)
                                    {
                                        pod.ImageUrl = atr.NodeValue;
                                    }
                                }
                                break;
                        }
                    }
                    catch { }
                }
                pod.Name = feedy.Title.Text;
                if (url.Equals(@"http://www.ynet.co.il/Integration/StoryRss194.xml"))
                {

                }
                if (pod.ImageUrl == "" || pod.ImageUrl.Equals(""))
                {
                    pod.ImageUrl = @"ms-appx:///Assets/empty.png";
                }
                try
                {
                    foreach (var item in feedy.Items)
                    {
                        try
                        {
                            var app = new PodcastApesode();
                            foreach (var link in item.Links)
                            {
                                if (link.Relationship.Equals("enclosure"))
                                {
                                    app.PlayUrl = link.Uri.ToString();
                                }
                            }
                            app.Name = item.Title.Text;
                            app.Published = item.PublishedDate;
                            app.PodcastRss = pod.Rss_url;
                            app.ThumbnailIconUrl = pod.ImageUrl;


                            if (pod.ImageUrl == null)
                            {

                            }
                            if (item.Summary != null && item.Summary.Text != "")
                            {
                                app.Discription = item.Summary.Text;
                            }
                            else
                            {
                                app.Discription = item.NodeValue;
                            }

                            foreach (var atrebute in item.ElementExtensions)
                            {
                                switch (atrebute.NodeName)
                                {
                                    case "duration":

                                        try
                                        {
                                            double durationDouble;

                                            if (!atrebute.NodeValue.Contains(':') && double.TryParse(atrebute.NodeValue, out durationDouble))
                                            {
                                                app.Total = ((int)durationDouble);
                                            }
                                            else
                                            {
                                                if (atrebute.NodeValue.Length <= 5 && atrebute.NodeValue.Contains(':'))
                                                {
                                                    TimeSpan span = new TimeSpan();
                                                    TimeSpan.TryParseExact(atrebute.NodeValue, "mm\\:ss", null, out span);
                                                    app.Total = ((int)span.TotalSeconds);
                                                }
                                                else
                                                {
                                                    app.Total = ((int)TimeSpan.Parse(atrebute.NodeValue).TotalSeconds);
                                                }
                                            }
                                        }
                                        catch
                                        {
                                            try
                                            {
                                                TimeSpan span = new TimeSpan();
                                                TimeSpan.TryParseExact(atrebute.NodeValue, "mm\\:ss", null, out span);
                                                app.Total = ((int)span.TotalSeconds);
                                            }
                                            catch
                                            {

                                            }
                                        }
                                        break;

                                    case "image":

                                        foreach (var elm in atrebute.AttributeExtensions)
                                        {
                                            if (elm.Name.Equals("href"))
                                            {
                                                app.ThumbnailIconUrl = elm.Value;
                                            }
                                        }
                                        break;
                                }

                            }


                            pod.PodcastApesodes.Add(app);
                        }
                        catch
                        {

                        }
                    }
                }
                catch
                {
                }

            }
            catch
            {

            }
            return pod;
        }

    }
}
