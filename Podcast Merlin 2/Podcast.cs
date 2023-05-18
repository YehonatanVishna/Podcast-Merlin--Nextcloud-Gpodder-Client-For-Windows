using Newtonsoft.Json;
using System.Collections.ObjectModel;

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
    }
}
