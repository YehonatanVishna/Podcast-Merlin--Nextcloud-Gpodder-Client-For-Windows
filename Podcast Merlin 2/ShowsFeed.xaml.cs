// Copyright (c) Microsoft Corporation and Contributors.
// Licensed under the MIT License.

using Microsoft.Toolkit.Collections;
using Microsoft.Toolkit.Uwp;
using Microsoft.UI.Xaml.Controls;
using Podcast_Merlin_Uwp;
using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Windows.ApplicationModel.Core;
using Windows.Media.Core;
using Windows.Media.Playback;
using Windows.Storage.Streams;
using Windows.UI.Xaml;
using Windows.UI.Xaml.Controls;
using Windows.UI.Xaml.Media;
using Windows.UI.Xaml.Navigation;
using static PodMerForWinUi.MainPage;

// To learn more about WinUI, the WinUI project structure,
// and more about our project templates, see: http://aka.ms/winui-project-info.

namespace PodMerForWinUi
{
    /// <summary>
    /// An empty page that can be used on its own or navigated to within a Frame.
    /// </summary>
    public sealed partial class ShowsFeed : Page
    {

        public ObservableCollection<ShowAndPodcast> showsLs = new ObservableCollection<ShowAndPodcast>();
        public object ls;
        //public IncrementalLoadingCollection<ShowsList, ShowAndPodcast> ShowsInc;
        //public List<Action> positions = MainPage.Actions.actions;

        public ShowsFeed()
        {
            this.InitializeComponent();
            //ShowsInc = new IncrementalLoadingCollection<ShowsList, ShowAndPodcast>(source: showsLs, 20);

        }

        //public void markPlayed()
        //{
        //    foreach (var item in showsLs)
        //    {
        //        foreach (var action in positions)
        //        {
        //            if (item.Show.PlayUrl.Equals(action.episode))
        //            {
        //                item.Show.Total = action.total;
        //                item.Show.Position = action.position;
        //            }
        //        }
        //    }
        //}
        protected override async void OnNavigatedTo(NavigationEventArgs e)
        {
            //showsLs = e.Parameter as ObservableCollection<ShowAndPodcast>;

            apesode_ListView.ItemsSource = e.Parameter;
            ls = e.Parameter;
        //    if(e.Parameter != null && e.Parameter.GetType().IsGenericType &&
        //e.Parameter.GetType().GetGenericTypeDefinition() == typeof(IncrementalLoadingCollection<,>))
        if(e.Parameter is IncrementalLoadingCollection<AllPodcastsShowsList, ShowAndPodcast>)
            {
                await ((IncrementalLoadingCollection<AllPodcastsShowsList, ShowAndPodcast>)e.Parameter).LoadMoreItemsAsync(100);
            }
            else
            {
                if(e.Parameter is IncrementalLoadingCollection<OnePodcastShowsList, ShowAndPodcast>)
                {
                    await (e.Parameter as IncrementalLoadingCollection<OnePodcastShowsList, ShowAndPodcast>).LoadMoreItemsAsync(100);
                }
            }
            //var ls = ShowsAndPodcasts.OrderByDescending((show) => { return show.Show.Published; });
            //showsLs.Clear();
            //foreach (var show in ls.Take(500))
            //{
            //    showsLs.Add(show);
            //}
            //markPlayed();


            //var ee = MainWindow.mediaPlayer_with_poster.ShowLastPlayed ;
            //if (MainWindow.mediaPlayer_with_poster.ShowLastPlayed != null)
            //{
            //    var show = MainWindow.mediaPlayer_with_poster.ShowLastPlayed;
            //    Task.Run(() =>
            //    {
            //        var same = showsLs.Where((showPod) => { return showPod.Show.PlayUrl.Equals(show.Show.PlayUrl); });
            //        if (same != null && same.Count() > 0)
            //        {
            //            var index = showsLs.IndexOf(same.FirstOrDefault());
            //            showsLs[index] = show;

            //        }
            //    });

            //}
            //apesode_ListView.ItemsSource = showsLs;
        }
        private Task lastSyncTask;
        private DispatcherTimer update_position_dispach_timer;
        private async void playShow(ShowAndPodcast PodcastAndShow)
        {
            var show = PodcastAndShow.Show;
            var podcast = PodcastAndShow.Podcast;
            apesode_ListView.SelectedItem = (show as PodcastApesode);
            MainWindow.mediaPlayer_with_poster.ImageUrl = show.ThumbnailIconUrl;
            MainWindow.mediaPlayer_with_poster.Track_name = (show as PodcastApesode).Name;
            if (MainWindow.mediaPlayer_with_poster.ShowLastPlayed != null)
            {
                try
                {
                    MainWindow.mediaPlayer_with_poster.ShowLastPlayed.Show.Position = (int)Math.Round(MainWindow.MediaPlayer.MediaPlayer.PlaybackSession.Position.TotalSeconds);
                    var pod = MainWindow.MediaPlayer.DataContext as ShowAndPodcast;
                    var pos = (int)Math.Round(MainWindow.MediaPlayer.MediaPlayer.PlaybackSession.Position.TotalSeconds);
                    Task.Run(() =>
                    {
                        if (lastSyncTask != null)
                        {
                            lastSyncTask.Wait();
                        }
                        var task = Task.Run(async () =>
                        {

                            await Sync.SyncService.SendAction(pod, pos);
                        });
                        lastSyncTask = task;
                    }
                    );
                    if (update_position_dispach_timer != null)
                    {
                        update_position_dispach_timer.Stop();
                    }

                }
                catch (System.NullReferenceException e)
                {

                }
            }
            update_position_dispach_timer = new DispatcherTimer();
            update_position_dispach_timer.Interval = new TimeSpan(0, 0, 1);
            update_position_dispach_timer.Tick += Update_position_dispach_timer_Tick;
            update_position_dispach_timer.Start();



            MainWindow.mediaPlayer_with_poster.Initialise_media_player();
            var sorce = new MediaPlaybackItem(MediaSource.CreateFromUri(new System.Uri(show.PlayUrl)));
            MediaItemDisplayProperties props = (sorce).GetDisplayProperties();
            props.Type = Windows.Media.MediaPlaybackType.Music;
            props.MusicProperties.Title = show.Name;
            props.MusicProperties.Artist = podcast.Name;
            props.Thumbnail = RandomAccessStreamReference.CreateFromUri(new System.Uri(show.ThumbnailIconUrl));
            props.MusicProperties.Genres.Add("Podcast");
            (sorce).ApplyDisplayProperties(props);

            MainWindow.MediaPlayer.Source = sorce;
            var playurl = (show).PlayUrl;
            MainWindow.MediaPlayer.DataContext = PodcastAndShow;
            MainWindow.MediaPlayer.MediaPlayer.PlaybackSession.Position = new System.TimeSpan(0, 0, show.Position);
            if (show.Total <= 0)
            {
            check:
                if (MainWindow.mediaPlayer_with_poster.Player.MediaPlayer.PlaybackSession.NaturalDuration.TotalSeconds != 0)
                    show.Total = (int)MainWindow.MediaPlayer.MediaPlayer.PlaybackSession.NaturalDuration.TotalSeconds;
                else
                {
                    await Task.Delay(50);
                    goto check;
                }
            }
            if (show.Position >= (show.Total - 3))
            {
                MainWindow.MediaPlayer.MediaPlayer.PlaybackSession.Position = new System.TimeSpan(0, 0, 0);
            }
            //var conatiner = apesode_ListView.ContainerFromIndex(showsLs.IndexOf(PodcastAndShow));
            //var bar = conatiner.FindDescendant("PodcastProgress") as ProgressBar;
            //// Define the binding source
            //Binding binding = new Binding() { Mode= BindingMode.TwoWay };
            //binding.Source = MainWindow.MediaPlayer.MediaPlayer.Position.TotalSeconds;

            //// Create the binding
            //bar.SetBinding(ProgressBar.ValueProperty, binding);



            //bool isSaved = false;
            //foreach (var position in positions)
            //{
            //    if (position.episode.Equals(playurl))
            //    {
            //        apesode.Started = position.position;
            //        MainWindow.MediaPlayer.MediaPlayer.Position = new System.TimeSpan(0, 0, position.position);
            //        isSaved = true;
            //    }
            //}


            //if (!isSaved)
            //{
            //    apesode.Started = 0;
            //}

            var a= (((apesode_ListView.ContainerFromItem(PodcastAndShow) as ListViewItem).ContentTemplateRoot as Panel).FindName("PodcastProgress") as Microsoft.UI.Xaml.Controls.ProgressBar);
            a.Visibility = Visibility.Visible;
            MainWindow.MediaPlayer.MediaPlayer.Play();
        }

        private void Update_position_dispach_timer_Tick(object sender, object e)
        {
            MainWindow.mediaPlayer_with_poster.ShowLastPlayed.Show.Position = (int)Math.Round(MainWindow.MediaPlayer.MediaPlayer.PlaybackSession.Position.TotalSeconds);
        }

        public ulong lastNav = 0;
        public ulong lastNav2 = 0;

        private async void apesode_ListView_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (((sender as ListView).SelectedItem) != null)
            {
                var show = ((ShowAndPodcast)(sender as ListView).SelectedItem).Show;
                var textColor = "";
                var Forground_color = (show_notes_box.Foreground as SolidColorBrush).Color;
                textColor = $"rgb({Forground_color.R},{Forground_color.G}, {Forground_color.B})";
                var backColor = (Application.Current.Resources["ApplicationPageBackgroundThemeBrush"] as SolidColorBrush).Color;
                var showNotesHtml = $@"
<html>
<head></head>
<body style="" color:{textColor}; background-color:rgb({backColor.R},{backColor.G},{backColor.B}); font-family: Arial, Helvetica, sans-serif; word-break: break-word; white-space: normal; "">
<style>
 /* width */
::-webkit-scrollbar {{width: 10px;
  border-radius: 10px;
}}

/* Track */
::-webkit-scrollbar-track {{background: rgb({backColor.R},{backColor.G},{backColor.B});
width: 1px;
}}

/* Track */
::-webkit-scrollbar-track:hover {{background: rgb({backColor.R},{backColor.G},{backColor.B});

}}

/* Handle */
::-webkit-scrollbar-thumb {{background: rgb(100,100,100);
  border-radius: 20px;

}}

/* Handle on hover */
::-webkit-scrollbar-thumb:hover {{background: #555;
  border-radius: 15px;
}}
}}
</style>
{show.Discription}
</body>
</html>
";
                await show_notes_box.EnsureCoreWebView2Async();
                show_notes_box.NavigateToString(showNotesHtml);
                show_notes_box.NavigationCompleted += async (webViewSender1, args1) =>
                {
                    show_notes_box.NavigationStarting += async (webViewSender, args) =>
                    {

                        // Get the URI of the link that was clicked
                        lastNav = args.NavigationId;
                        var uri = new Uri(args.Uri);
                        if (uri.HostNameType == UriHostNameType.Dns && (args.NavigationId != lastNav || args.NavigationId != lastNav2))
                        {
                            lastNav2 = lastNav;
                            lastNav = args.NavigationId;
                            // Cancel the navigation
                            args.Cancel = true;


                            // Open the link in the default external browser
                            //if (await Windows.System.Launcher.LaunchUriForResultsForUserAsync(Windows.System.User.GetDefault(), uri, new Windows.System.LauncherOptions() { IgnoreAppUriHandlers = true , appnull)
                            //{
                            var success = await Windows.System.Launcher.LaunchUriAsync(uri, new Windows.System.LauncherOptions() { IgnoreAppUriHandlers = true, DisplayApplicationPicker = false });
                            if (success)
                            {
                                // The link was opened successfully
                            }
                            else
                            {
                                // An error occurred, the link could not be opened
                            }
                        }
                        else
                        {
                            if (!uri.Scheme.Equals("data"))
                            {
                                // Cancel the navigation
                                args.Cancel = true;
                                show_notes_box.NavigateToString(showNotesHtml);

                            }
                        }

                        //}

                    };

                };
            }
        }

        private void Show_notes_box_NavigationCompleted(WebView2 sender, Microsoft.Web.WebView2.Core.CoreWebView2NavigationCompletedEventArgs args)
        {
            throw new NotImplementedException();
        }

        private void show_ditailes_view_DataContextChanged(FrameworkElement sender, DataContextChangedEventArgs args)
        {

        }

        private void Play_btn_Click(object sender, RoutedEventArgs e)
        {
            var podcast = ((ShowAndPodcast)(sender as Button).DataContext);
            playShow(podcast);
            apesode_ListView.SelectedItem = podcast;
        }

        private void apesode_ListView_Loaded(object sender, RoutedEventArgs e)
        {
            //apesode_ListView.IncrementalLoadingThreshold = 50;
            //apesode_ListView.IncrementalLoadingTrigger = IncrementalLoadingTrigger.Edge;
            //apesode_ListView.ItemsSource = showsLs;
            //markPlayed();
            //apesode_ListView.SelectedIndex = 0;

        }

        private void ScrollViewer_ViewChanged(object sender, ScrollViewerViewChangedEventArgs e)
        {
            if(apesode_ListView.ItemsSource is AllPodcastsShowsList)
            {
                var scrollViewer = (ScrollViewer)sender;
                if (scrollViewer.VerticalOffset == scrollViewer.ScrollableHeight)
                {
                    try
                    {
                        apesode_ListView.LoadMoreItemsAsync();
                    }
                    catch
                    {

                    }
                }
                    
            }
        }

        private async void apesode_ListView_ContainerContentChanging(ListViewBase sender, ContainerContentChangingEventArgs args)
        {
            if (args.ItemIndex == apesode_ListView.Items.Count - 10)
            {
                await apesode_ListView.LoadMoreItemsAsync();
            }
        }
    }
}
