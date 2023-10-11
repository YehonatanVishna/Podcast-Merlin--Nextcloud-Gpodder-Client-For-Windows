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
            MainWindow.RefreshFunc = () =>  Task.Run(()=> { var a = 1 + 1; }) ;
            var ParameterList = e.Parameter as List<object>;
            apesode_ListView.ItemsSource = ParameterList[1];
            pageIncrementalLoadingSorce = ParameterList[1];
            var PageType = (FeedContent) ParameterList.FirstOrDefault();
            if(PageType == FeedContent.AllPodcasts)
            {
                App.MainWindow.WindowTitleText.Name = "Podcast feed";
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
            //Refresh_btn.Command = new Refresh_Btn_Command();
            //Refresh_btn.CommandParameter = this;
            apesode_ListView.SelectedIndex = 0;
            //(ParameterList[1] as IncrementalLoadingCollection<AllPodcastsShowsList, object>).LoadMoreItems(15);


            MainWindow.RefreshFunc = () => Refresh();
        }
        //class Refresh_Btn_Command : ICommand
        //{
        //    public event EventHandler CanExecuteChanged;
        //    public static Task LastRefresh;
        //    public bool CanExecute(object parameter)
        //    {
        //        return ((LastRefresh == null) || (LastRefresh != null && LastRefresh.IsCompleted));
        //        return false;
        //    }

        //    public void Execute(object parameter)
        //    {
        //        ShowsFeed showsFeed = parameter as ShowsFeed;
        //        if(showsFeed.feedContentType == FeedContent.OnePodcast)
        //        {
                    
        //        }
        //    }
        //}
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
                    throw new Exception("Show doesn't have a play url");
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
                        pod.Show.PlayBrush = new SolidColorBrush(await getRightColor(0));
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
                show.PlayBrush = new SolidColorBrush(await getRightColor(3)) ;
                show.IsPlaying = true;
                var a = (((apesode_ListView.ContainerFromItem(PodcastAndShow) as ListViewItem).ContentTemplateRoot as FrameworkElement).FindName("PodcastProgress") as Microsoft.UI.Xaml.Controls.ProgressBar);
                a.Visibility = Visibility.Visible;
                MainWindow.MediaPlayer.MediaPlayer.Play();
            }
            catch
            {
                var errorDialog = new ContentDialog() { Title = "There seems to be a problem playing this show.", Content = "Please try again later.", CloseButtonText = "Ok" };
                errorDialog.ShowAsync();
            }
        }

        private void Update_position_dispach_timer_Tick(object sender, object e)
        {
            MainWindow.mediaPlayer_with_poster.ShowLastPlayed.Show.Position = (int)Math.Round(MainWindow.MediaPlayer.MediaPlayer.PlaybackSession.Position.TotalSeconds);
        }

        public ulong lastNav = 0;
        public ulong lastNav2 = 0;

        public static async Task<Color> getRightColor(int level=2)
        {
            Color linkColor;
            await App.MainWindow.Dispatcher.RunAsync(Windows.UI.Core.CoreDispatcherPriority.Low, () => {
                linkColor = (Color)(Application.Current.Resources["SystemAccentColor"]);
                if (level != 0)
                {
                    if (App.Current.RequestedTheme == ApplicationTheme.Dark)
                    {
                        if (level > 0)
                            linkColor = (Color)(Application.Current.Resources["SystemAccentColorLight" + level]);
                        else
                            linkColor = (Color)(Application.Current.Resources["SystemAccentColorDark" + -1 * level]);
                    }
                    else
                    {
                        if (level > 0)
                            linkColor = (Color)(Application.Current.Resources["SystemAccentColorDark" +  level]);
                        else
                            linkColor = (Color)(Application.Current.Resources["SystemAccentColorLight" + -1 * level]);
                    }
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

        private async void apesode_ListView_ContainerContentChanging(ListViewBase sender, ContainerContentChangingEventArgs args)
        {
            if (args.ItemIndex == apesode_ListView.Items.Count - 10)
            {
                await apesode_ListView.LoadMoreItemsAsync();
            }
        }

        private async Task Refresh()
        {
            await Task.Run(async () =>
            {

                
                if (feedContentType == FeedContent.OnePodcast)
                {
                    var PodsDb = new Sql.SqlLite.SqlLitePodcasts();
                    await PodsDb.init();
                    var podcast = await PodsDb.get_podcast_by_id( (feedContent as Podcast).ID);
                    var newPod = await Podcast.get_podcast_from_url_string(podcast.Rss_url);

                    await PodsDb.save_to_db_one_podcast_and_all_its_shows(newPod, podcast);
                    await Sync.SyncService.get_actions_and_put_them_on_file(false);
                    await Dispatcher.RunAsync(Windows.UI.Core.CoreDispatcherPriority.Normal, async () =>
                    {
                        await (pageIncrementalLoadingSorce as IncrementalLoadingCollection<OnePodcastShowsList, ShowAndPodcast>).RefreshAsync();
                        await apesode_ListView.LoadMoreItemsAsync();
                    });
                    }
                else
                {
                    if (feedContentType == FeedContent.AllPodcasts)
                    {
                        await MainWindow.mainPage.pull_new_info_about_podcast_put_on_file(MainPage.Podcasts);
                        await Sync.SyncService.get_actions_and_put_them_on_file();
                        await Dispatcher.RunAsync(Windows.UI.Core.CoreDispatcherPriority.Normal, async () =>
                        {
                            await (pageIncrementalLoadingSorce as IncrementalLoadingCollection<AllPodcastsShowsList, ShowAndPodcast>).RefreshAsync();
                        });
                    }
                }

            });
        }

        private void ShowInfoItem_RightTapped(object sender, Windows.UI.Xaml.Input.RightTappedRoutedEventArgs e)
        {
            ShowAndPodcast showAndPodcast = (sender as FrameworkElement).DataContext as ShowAndPodcast;
            if (!showAndPodcast.Show.IsPlaying)
            {
                apesode_ListView.SelectedItem = (sender as FrameworkElement).DataContext;
                var menu = new MenuFlyout();
                var mark_as_finished = new MenuFlyoutItem() { Text = "mark as finished" };
                mark_as_finished.DataContext = (sender as FrameworkElement).DataContext;
                mark_as_finished.Click += Mark_as_played_Click;


                var mark_as_unplayed = new MenuFlyoutItem() { Text = "mark as unplayed" };
                mark_as_unplayed.DataContext = (sender as FrameworkElement).DataContext;
                mark_as_unplayed.Click += Mark_as_unplayed_Click;

                if (!(showAndPodcast.Show.Position <= 0))
                {
                    menu.Items.Add(mark_as_unplayed);
                }
                if (!(showAndPodcast.Show.Position >= showAndPodcast.Show.Total))
                {
                    menu.Items.Add(mark_as_finished);
                }

                UIElement b = sender as UIElement;
                b.ContextFlyout = menu;
                menu.ShowAt(sender as UIElement, e.GetPosition(sender as UIElement));
            }

        }

        private void Mark_as_unplayed_Click(object sender, RoutedEventArgs e)
        {
            ShowAndPodcast showPod = (sender as FrameworkElement).DataContext as ShowAndPodcast;
            showPod.Show.Position = 0;
            Task.Run(async () =>
            {
                try
                {
                    await Sync.SyncService.SendAction(showPod, 0);
                }
                catch
                {

                }
            });
        }

        private void Mark_as_played_Click(object sender, RoutedEventArgs e)
        {
            ShowAndPodcast showPod = (sender as FrameworkElement).DataContext as ShowAndPodcast;
            showPod.Show.Position = showPod.Show.Total;
            Task.Run(async () =>
            {
                try
                {
                    await Sync.SyncService.SendAction(showPod, showPod.Show.Total);
                }
                catch
                {

                }
            });
            
        }
    }
}
