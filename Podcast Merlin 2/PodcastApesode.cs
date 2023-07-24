using CommunityToolkit.Mvvm.ComponentModel;
using Podcast_Merlin_Uwp;
using System;
using System.Linq;
using System.Threading.Tasks;
using Windows.UI;
using Windows.UI.WebUI;
using Windows.UI.Xaml;
using Windows.UI.Xaml.Media;

namespace PodMerForWinUi
{
    public class PodcastApesode : ObservableObject
    {
        private SolidColorBrush playColor ;
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
        public static SolidColorBrush DefaultColor;
        private static bool hasCalcColor =false;
        public PodcastApesode()
        {
            if (!hasCalcColor)
            {
                var ts = Task.Run(async () => { return await ShowsFeed.getRightColor(0); });
                ts.Wait();
                var tsk = App.MainWindow.Dispatcher.RunAsync(Windows.UI.Core.CoreDispatcherPriority.Low, () =>
                {
                    playColor = new SolidColorBrush(ts.Result);
                });
                tsk.AsTask().Wait();
                DefaultColor = playColor;
                hasCalcColor = true;
            }
            else
            {
                playColor = DefaultColor;
            }
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
        public string getFullNumberString(int a)
        {
            if (a <= 9 && a>=0) {
                return "0" + a.ToString();
            }
            return a.ToString();
        }
        public string FormattedPublishedDate
        {
            get
            {
                return $@"{getFullNumberString(published.Day)}/{getFullNumberString(published.Month)}/{getFullNumberString(published.Year)}
{getFullNumberString(published.Hour)}:{getFullNumberString(published.Minute)}";
            }
        }
        //identical
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
        //almost the same, probably the same
        public bool isSameShow(PodcastApesode Show){
            var show = this;
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
        }

    }
}
