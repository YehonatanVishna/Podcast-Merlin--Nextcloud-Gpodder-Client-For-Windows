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
//using System.Drawing;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Input;
using Windows.ApplicationModel.Core;
using Windows.Media.Core;
using Windows.Media.Playback;
using Windows.Storage.Streams;
using Windows.UI;
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
        public FeedContent feedContentType;
        public object feedContent;
        public object pageIncrementalLoadingSorce;
        public ShowsFeed()
        {
            this.InitializeComponent();
            
        }


        protected override async void OnNavigatedTo(NavigationEventArgs e)
        {
            
            var ParameterList = e.Parameter as List<object>;
            apesode_ListView.ItemsSource = ParameterList[1];
            pageIncrementalLoadingSorce = ParameterList[1];
            var PageType = (FeedContent) ParameterList.FirstOrDefault();
            if(PageType == FeedContent.AllPodcasts)
            {
                App.MainWindow.WindowTitleText.Name = "podcast feed";
                await ((IncrementalLoadingCollection<AllPodcastsShowsList, ShowAndPodcast>)ParameterList[1]).LoadMoreItemsAsync(10);
                
            }
            else
            {
                if(PageType == FeedContent.OnePodcast)
                {
                    try
                    {
                        await (ParameterList[1] as IncrementalLoadingCollection<OnePodcastShowsList, ShowAndPodcast>).LoadMoreItemsAsync(100);
                        App.MainWindow.WindowTitleText.Name = (ParameterList[1] as IncrementalLoadingCollection<OnePodcastShowsList, ShowAndPodcast>).FirstOrDefault().Podcast.Name;

                    }
                    catch
                    {

                    }
                    feedContent = ParameterList[2];
                }
            }
            feedContentType = PageType;
            Refresh_btn.Command = new Refresh_Btn_Command();
            Refresh_btn.CommandParameter = this;
            apesode_ListView.SelectedIndex = 0;
            //(ParameterList[1] as IncrementalLoadingCollection<AllPodcastsShowsList, object>).LoadMoreItems(15);
        }
        class Refresh_Btn_Command : ICommand
        {
            public event EventHandler CanExecuteChanged;
            public static Task LastRefresh;
            public bool CanExecute(object parameter)
            {
                return ((LastRefresh == null) || (LastRefresh != null && LastRefresh.IsCompleted));
                return false;
            }

            public void Execute(object parameter)
            {
                ShowsFeed showsFeed = parameter as ShowsFeed;
                if(showsFeed.feedContentType == FeedContent.OnePodcast)
                {
                    
                }
            }
        }
        private Task lastSyncTask;
        private DispatcherTimer update_position_dispach_timer;
        private async void playShow(ShowAndPodcast PodcastAndShow)
        {
            try
            {
                var show = PodcastAndShow.Show;
                var podcast = PodcastAndShow.Podcast;
                if(show.PlayUrl ==null || show.PlayUrl == "")
                {
                    throw new Exception("show doesnt have a play url");
                }
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
                        pod.Show.PlayBrush = new SolidColorBrush(await getRightColor());
                        pod.Show.IsPlaying = false;
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
                show.PlayBrush = new SolidColorBrush(Colors.ForestGreen);
                show.IsPlaying = true;
                var a = (((apesode_ListView.ContainerFromItem(PodcastAndShow) as ListViewItem).ContentTemplateRoot as Panel).FindName("PodcastProgress") as Microsoft.UI.Xaml.Controls.ProgressBar);
                a.Visibility = Visibility.Visible;
                MainWindow.MediaPlayer.MediaPlayer.Play();
            }
            catch
            {
                var errorDialog = new ContentDialog() { Title = "There Seems To Be A Problem Playing This Show", Content = "please try again later", CloseButtonText = "ok" };
                errorDialog.ShowAsync();
            }
        }

        private void Update_position_dispach_timer_Tick(object sender, object e)
        {
            MainWindow.mediaPlayer_with_poster.ShowLastPlayed.Show.Position = (int)Math.Round(MainWindow.MediaPlayer.MediaPlayer.PlaybackSession.Position.TotalSeconds);
        }

        public ulong lastNav = 0;
        public ulong lastNav2 = 0;

        public static async Task<Color> getRightColor()
        {
            Color linkColor;
            await App.MainWindow.Dispatcher.RunAsync(Windows.UI.Core.CoreDispatcherPriority.Low, () => {
                linkColor = (Color)(Application.Current.Resources["SystemAccentColor"]);
                if (App.Current.RequestedTheme == ApplicationTheme.Dark)
                    linkColor = (Color)(Application.Current.Resources["SystemAccentColorLight2"]);
                else
                {
                    linkColor = (Color)(Application.Current.Resources["SystemAccentColorDark2"]);
                }
            });

            return linkColor;
        }
        private async void apesode_ListView_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (((sender as ListView).SelectedItem) != null)
            {
                show_notes_box.PointerWheelChanged += Show_notes_box_PointerWheelChanged;
                this.SizeChanged += ShowsFeed_SizeChanged;
                var show = ((ShowAndPodcast)(sender as ListView).SelectedItem).Show;
                var textColor = "";
                var Forground_color = (show_notes_box.Foreground as SolidColorBrush).Color;
                textColor = $"rgb({Forground_color.R},{Forground_color.G}, {Forground_color.B})";
                var backColor = (Application.Current.Resources["ApplicationPageBackgroundThemeBrush"] as SolidColorBrush).Color;
                var linkColor = await getRightColor();
                var showNotesHtml = $@"
<html>
<head></head>
<body style="" color:{textColor}; background-color:rgb({backColor.R},{backColor.G},{backColor.B}); font-family: Arial, Helvetica, sans-serif; word-break: break-word; white-space: normal; "">
<style>

a {{
color: rgb({linkColor.R},{linkColor.G},{linkColor.B});
}}
/* Hide the default scrollbar */
::-webkit-scrollbar {{width: 0;
    height: 0;
}}
</style>
<div id=""cont"">
{show.Discription}
</div>
</body>
</html>
";
                await show_notes_box.EnsureCoreWebView2Async();
                show_notes_box.NavigateToString(showNotesHtml);
                
                show_notes_box.NavigationCompleted += async (webViewSender1, args1) =>
                {
                    SetWebViewHeight();
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
                                show_notes_box.Height = await GetWebViewContentHeightAsync(show_notes_box);

                            }
                        }

                        //}

                    };

                };
            }
        }

        private void ShowsFeed_SizeChanged(object sender, SizeChangedEventArgs e)
        {
            SetWebViewHeight();
        }

        private async void SetWebViewHeight()
        {
           double contHight = await GetWebViewContentHeightAsync(show_notes_box);
            if(contHight > show_ditailes_view.ActualSize.Y)
            {
                show_notes_box.Height = contHight + 10;
            }
            else
            {
                show_notes_box.Height = show_ditailes_view.Height;
            }
        }
        private async Task<double> GetWebViewContentHeightAsync(WebView2 webView)
        {
            // Execute JavaScript code within the WebView2 to retrieve the content height
            string script = @"document.getElementById(""cont"").clientHeight.toString() + "".0"";";

            try
            {
                var result = (await webView.ExecuteScriptAsync(script)).Replace('"',' ');
                if (double.TryParse(result, out double contentHeight))
                {
                    return contentHeight + 20;
                }
            }
            catch (Exception ex)
            {
            }

            return 0; // Return a default height if retrieval fails
        }
        private void Show_notes_box_PointerWheelChanged(object sender, Windows.UI.Xaml.Input.PointerRoutedEventArgs e)
        {
            int wheelDelta = e.GetCurrentPoint(sender as UIElement).Properties.MouseWheelDelta;
                show_ditailes_view.ChangeView(null, show_ditailes_view.VerticalOffset - wheelDelta, null);
        }

        private void Show_notes_box_ManipulationDelta(object sender, Windows.UI.Xaml.Input.ManipulationDeltaRoutedEventArgs e)
        {
            //// Update the ScrollViewer's position based on the manipulation delta
            //ScrollViewer scrollViewer = show_ditailes_view; // Replace "MyScrollViewer" with the actual name of your ScrollViewer control
            //scrollViewer.ChangeView(scrollViewer.HorizontalOffset - e.Delta.Translation.X,
            //                        scrollViewer.VerticalOffset,
            //                        null);
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

        private async void Refresh_btn_Click(object sender, RoutedEventArgs e)
        {
            await Task.Run(async () =>
            {
                Dispatcher.RunAsync(Windows.UI.Core.CoreDispatcherPriority.Normal, async () =>
                {
                    refresh_indecator.IsActive = true;
                });
                if (feedContentType == FeedContent.OnePodcast)
                {
                    var podcast = feedContent as Podcast;
                    var newPod = await Podcast.get_podcast_from_url_string(podcast.Rss_url);
                    var PodsDb = new Sql.SqlLite.SqlLitePodcasts();
                    await PodsDb.init();
                    await PodsDb.save_to_db_one_podcast_and_all_its_shows(newPod, podcast);
                    await Dispatcher.RunAsync(Windows.UI.Core.CoreDispatcherPriority.Normal, async () =>
                    {
                        await (pageIncrementalLoadingSorce as IncrementalLoadingCollection<OnePodcastShowsList, ShowAndPodcast>).RefreshAsync();
                    });
                    }
                else
                {
                    if (feedContentType == FeedContent.AllPodcasts)
                    {
                        await MainWindow.mainPage.pull_new_info_about_podcast_put_on_file(MainPage.Podcasts);
                        await Dispatcher.RunAsync(Windows.UI.Core.CoreDispatcherPriority.Normal, async () =>
                        {
                            await (pageIncrementalLoadingSorce as IncrementalLoadingCollection<AllPodcastsShowsList, ShowAndPodcast>).RefreshAsync();
                        });
                    }
                }
                await Dispatcher.RunAsync(Windows.UI.Core.CoreDispatcherPriority.Normal, async () =>
                {
                    apesode_ListView.LoadMoreItemsAsync();
                    refresh_indecator.IsActive = false;
                });
            });
        }
    }
}
