using CommunityToolkit.Mvvm.ComponentModel;
using System;
using Windows.UI;
using Windows.UI.WebUI;
using Windows.UI.Xaml;
using Windows.UI.Xaml.Media;

namespace PodMerForWinUi
{
    public class PodcastApesode : ObservableObject
    {
        private SolidColorBrush playColor = new SolidColorBrush( ShowsFeed.getRightColor());
        private bool isPlaying;
        private int iD = 0;
        private int podcastID = 0;
        private string name = "";
        private string playUrl = "";
        private string id = "";
        private string thumbnailIconUrl;
        private string podcastRss;
        private DateTimeOffset published;
        private string discription = "";
        private int position = 0;
        private int started = 0;
        private int total = 0;
        public Visibility visibility= Visibility.Collapsed;

        public PodcastApesode()
        {
        }

        public string Name { get => name; set { SetProperty(ref name, value); } }
        public string PlayUrl { get => playUrl; set { SetProperty(ref playUrl, value); } }
        public string Id { get => id; set { SetProperty(ref id, value); } }
        public DateTimeOffset Published { get => published; set { SetProperty(ref published, value); } }
        public string Discription { get => discription; set { SetProperty(ref discription, value); } }
        public int Started { get => started; set { SetProperty(ref started, value); } }
        public int Total { get => total; set { SetProperty(ref total, value); } }
        public int ID { get => iD; set { SetProperty(ref iD, value); } }
        public int PodcastID { get => podcastID; set { SetProperty(ref podcastID, value); } }
        public string PodcastRss { get => podcastRss; set { SetProperty(ref podcastRss, value); } }
        public string ThumbnailIconUrl { get => thumbnailIconUrl; set { SetProperty(ref thumbnailIconUrl, value); } }
        public int Position { get => position; set {
                if (value > 0)
                {
                    Vis = Visibility.Visible;
                }
                SetProperty(ref position, value);

            } }
        private Func<int, int> getVisualState = (pos) =>
        {
            if (pos != 0)
            {
                return 0;
            }
            return 1;
        };
        public int Progress
        {
            get
            {
                try
                {
                    return (int)((double.Parse(position.ToString()) / double.Parse(total.ToString())) * 100);

                }
                catch
                {
                    return 0;
                }
            }
        }

        public int Visual_state { get => visual_state; set => visual_state = value; }
        public Visibility Vis { get => visibility; set { SetProperty(ref visibility, value); } }

        public SolidColorBrush PlayBrush
        {
            get
            {
                return playColor;
            }
            set
            {
                SetProperty(ref playColor, value);
            }
        }
        public bool IsPlaying { get => isPlaying; set => SetProperty(ref isPlaying, value); }

        private int visual_state = 0;
        public bool equals(PodcastApesode show)
        {
            bool playS = playUrl.Equals(show.playUrl);
            bool IDS = ID == show.ID;
            bool PodIDS = PodcastID == show.PodcastID;
            bool totalS = total == show.Total;
            bool startedS = started == show.started;
            bool posS = position == show.position;
            bool disS = Discription.Equals(show.discription);
            bool NameS = Name.Equals(show.Name);
            bool pubS = Published.Equals(show.published);
            return playS && IDS && PodIDS && totalS && startedS && posS && disS && NameS && pubS;
        }

    }
}
