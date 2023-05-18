// Copyright (c) Microsoft Corporation and Contributors.
// Licensed under the MIT License.

using Microsoft.Toolkit.Collections;
using Microsoft.Toolkit.Uwp;
using Microsoft.UI.Xaml.Controls;
using Podcast_Merlin_Uwp;
using PodMerForWinUi;
using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Input;
using Windows.UI.Core;
using Windows.UI.Xaml;
using Windows.UI.Xaml.Controls;
using Windows.UI.Xaml.Data;
using Windows.UI.Xaml.Documents;
using Windows.UI.Xaml.Input;
using Windows.UI.Xaml.Navigation;
using static PodMerForWinUi.MainPage;

// To learn more about WinUI, the WinUI project structure,
// and more about our project templates, see: http://aka.ms/winui-project-info.

namespace PodMerForWinUi
{
    /// <summary>
    /// An empty page that can be used on its own or navigated to within a Frame.
    /// </summary>
    public sealed partial class MainPage : Page
    {
        public class loginPageDitales
        {
            public string login_url = "";
            public string token = "";
            public string poll_url = "";
            public string login_name = "";
            public string app_password = "";
            public string server = "";
            public loginPageDitales()
            {

            }
        }
        public static loginPageDitales Server_Details;
        public static Windows.Storage.ApplicationDataContainer localSettings =
    Windows.Storage.ApplicationData.Current.LocalSettings;
        public static Windows.Storage.StorageFolder localFolder =
            Windows.Storage.ApplicationData.Current.LocalFolder;
        public Frame frame = new Frame();
        public static ActionsResponse Actions;
        public static ObservableCollection<Podcast> Podcasts = new ObservableCollection<Podcast>();
        private static PodMerForWinUi.Sql.SqlLite.SqlLitePodcasts PodsDb = new PodMerForWinUi.Sql.SqlLite.SqlLitePodcasts();
        private static PodMerForWinUi.Sql.SqlLite.SqlLitePodcastsShows ShowsDb = new PodMerForWinUi.Sql.SqlLite.SqlLitePodcastsShows();
        //public static CollectionViewSource PodcastsSorce = new CollectionViewSource();

        public MainPage()
        {
            this.InitializeComponent();
            MainWindow.mainPage = this;
            localSettings =
    Windows.Storage.ApplicationData.Current.LocalSettings;
            localFolder =
            Windows.Storage.ApplicationData.Current.LocalFolder;
            Podcasts_Grid.ItemsSource = Podcasts;
            if (localSettings.Values["IsNextCloudInitAlready?"] == null || localSettings.Values["IsNextCloudInitAlready?"].ToString().Equals(bool.FalseString))
            {
                StartNextCloudConfig();
            }
            else
            {
                Server_Details = new loginPageDitales();
                Server_Details.server = localSettings.Values["NextCloud_server"].ToString();
                Server_Details.login_name = localSettings.Values["login_name"].ToString();
                Server_Details.app_password = localSettings.Values["app_password"].ToString();
                Task.Run(async () =>
                {
                    await PodsDb.init();
                    await ShowsDb.initAsync();
                }).Wait();
                putPodcastsOnScreen();

            }

        }
        public void loadingCompleted()
        {
            Dispatcher.RunAsync(CoreDispatcherPriority.Normal , () =>
            {
                goto_feed.Visibility = Visibility.Visible;
                addPodcast.Visibility = Visibility.Visible;
            });
        }
        public async Task<ObservableCollection<Podcast>> use_cashed_podcasts_and_put_them_on_screen()
        {
            //var stop = new Stopwatch();
            //stop.Start();
            var Pods = await PodsDb.get_all_podcasts();
            //var ord = Pods.OrderBy((podcast) => { return podcast.Name; });
            //var Podcasts = new ObservableCollection<Podcast>();
            //int i = 0;
            //foreach (var pod in ord)
            //{
            //    try
            //    {
            //        //pod.PodcastApesodes = await ShowsDb.get_all_shows_for_Podcast(pod); 
            //        Podcasts.Add(pod);
            //    }
            //    catch
            //    {

            //    }
            //    i++;
            //}
            //Task.WaitAll(Tasks);
            //stop.Stop();
            return Pods;
        }
        public async Task putPodcastsOnScreen()
        {
            var Pods = new ObservableCollection<Podcast>();
            try
            {
                if (localSettings.Values["lastCheckedPodcasts"]!= null && (DateTime.Now - DateTime.Parse(localSettings.Values["lastCheckedPodcasts"].ToString())).TotalHours < 2)
                {
                    //Podcasts_Grid.ShowsScrollingPlaceholders = true;
                    var Podcastss = await Task.Run(use_cashed_podcasts_and_put_them_on_screen);
                    Actions = await Sync.SyncService.get_actions_and_put_them_on_file();
                    Dispatcher.RunAsync(
CoreDispatcherPriority.High,
() =>
{
    Podcasts.Clear();
    foreach (var item in Podcastss)
    {
        Podcasts.Add(item);
    };
}
);
                    loadingCompleted();


                    Podcasts_Grid.ItemsSource = await Task.Run(async () => { await pull_new_info_about_podcast_put_on_file(Podcastss); return use_cashed_podcasts_and_put_them_on_screen(); });
                    update_loading_ring.IsActive = false;

                }
                else
                {
                    var Podcastss = await Task.Run(use_cashed_podcasts_and_put_them_on_screen);
                    Actions = await Sync.SyncService.get_actions_and_put_them_on_file();
                    Podcasts.Clear();
                    foreach (var item in Podcastss)
                    {
                        Podcasts.Add(item);
                    }
                    if(Podcasts.Count > 0)
                    {
                        loadingCompleted();
                    }
                    throw new Exception();
                }

            }
            catch
            {
                update_loading_ring.IsActive = true;
                if(localSettings.Values["lastCheckedPodcasts"] != null)
                {
                    Podcasts_Grid.ItemsSource = await use_cashed_podcasts_and_put_them_on_screen();
                }
                await Task.Run(() => pull_new_info_about_podcast_put_on_file(Podcasts));
                Actions = await Sync.SyncService.get_actions_and_put_them_on_file();
                Podcasts_Grid.ItemsSource = await use_cashed_podcasts_and_put_them_on_screen();
                loadingCompleted();
                await Sync.SyncService.SyncCashedActions();
                update_loading_ring.IsActive = false;
            }


        }
        private async Task add_podcast_on_end(string url, ObservableCollection<Podcast> pods)
        {
            pods.Add(await get_podcast_from_url_string(url));
        }
        public static bool IsSameShow(PodcastApesode show, PodcastApesode Show)
        {
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
        public static async Task saveToDb(ObservableCollection<Podcast> Pods_new, ObservableCollection<Podcast> Pods_old)
        {
            var ShowList = new List<PodcastApesode>();
            foreach (var pod in Pods_new)
            {
                try
                {
                    pod.ID = await PodsDb.add(pod);
                }
                catch
                {
                    await PodsDb.update(pod);
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
                        var oldShow = oldPod.PodcastApesodes.Where((Show) => IsSameShow(show, Show)).FirstOrDefault();
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

                var result = await ShowsDb.SaveBulck(ShowList);
            }
            catch
            {

            }
        }
        public async Task pull_new_info_about_podcast_put_on_file(ObservableCollection<Podcast> currentPodcasts)
        {
            //var Pods = currentPodcasts;
            var Pods = await PodsDb.get_all_podcasts();
            foreach (var pod in Pods)
            {
                pod.PodcastApesodes = await ShowsDb.get_all_shows_for_Podcast(pod);
            }
            var podcasts_rss_url = await Sync.SyncService.get_podcasts_urls();
            var newPods = new ObservableCollection<Podcast>();
            var Tasks = new List<Task>();
            foreach (var url in podcasts_rss_url)
            {
                Tasks.Add(Task.Run(async ()=> await add_podcast_on_end(url, newPods)));
                //Pods.Add(await get_podcast_from_url_string(url));
            }
            Task.WaitAll(Tasks.ToArray());

            await saveToDb(Pods_new: newPods, Pods_old: Pods);

            Newtonsoft.Json.JsonSerializer jsonSerializer = new Newtonsoft.Json.JsonSerializer()
            {
                Formatting = Newtonsoft.Json.Formatting.Indented,

            };

            //Podcasts_Grid.ItemsSource = Pods;


            Pods = await PodsDb.get_all_podcasts();
            foreach (var pod in Pods)
            {
                pod.PodcastApesodes = await ShowsDb.get_all_shows_for_Podcast(pod);
            }
            Podcasts = Pods;
            var textWriter = new StringWriter();

            Windows.Storage.StorageFolder storageFolder = Windows.Storage.ApplicationData.Current.LocalFolder;
            Windows.Storage.StorageFile sampleFile = await storageFolder.CreateFileAsync("podcasts.json", Windows.Storage.CreationCollisionOption.ReplaceExisting);
            await Windows.Storage.FileIO.WriteTextAsync(sampleFile, Newtonsoft.Json.JsonConvert.SerializeObject(Pods.ToList()));

            localSettings.Values["lastCheckedPodcasts"] = DateTime.Now.ToString();


        }
        public async Task<Podcast> get_podcast_from_url_string(string url)
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
        public async void StartNextCloudConfig()
        {
            //await Task.Delay(2222);
            if (localSettings.Values["IsNextCloudInitAlready?"] == null || localSettings.Values["IsNextCloudInitAlready?"].ToString().Equals(bool.FalseString))
            {
                var father = new StackPanel();
                var urlTextBox = new TextBox();
                father.Children.Add(urlTextBox);
                Binding UrlBinding = new Binding();
                TextBlock richTextBlock = new TextBlock() { TextWrapping = TextWrapping.Wrap };
                richTextBlock.Inlines.Add(new Run() { Text = @"Don't have your own nextcloud server? 
Go over to " });
                var hyper = new Hyperlink();
                hyper.NavigateUri = new Uri(@"https://nextcloud.com/sign-up/");
                hyper.Inlines.Add(new Run() { Text = "this link" });
                richTextBlock.Inlines.Add(hyper);
                richTextBlock.Inlines.Add(new Run() { Text = @", select Webo.hosting as your provider and create your own private syncing account." });
                father.Children.Add(richTextBlock);
                var getUrl = new ContentDialog() { Title = "please enter the adress of your nextcloud instance", CloseButtonText = "cancel", SecondaryButtonText = "ok", SecondaryButtonCommand = new continueUrlRegestration(), SecondaryButtonCommandParameter = urlTextBox, Content = father };
                await getUrl.ShowAsync();
            check_again:
                if (Server_Details != null && Server_Details.login_url != "" && Server_Details.login_url != null)
                {
                    var webWindowLogin = new WebView2() { Source = new Uri(Server_Details.login_url.ToString()) };
                    webWindowLogin.NavigationCompleted += WebWindowLogin_NavigationCompleted;
                    webWindowLogin.DataContext = Frame;
                    Frame.Content = webWindowLogin;
                }
                else
                {
                    await Task.Delay(10);
                    goto check_again;
                }

            }
        }

        private async void WebWindowLogin_NavigationCompleted(WebView2 sender, Microsoft.Web.WebView2.Core.CoreWebView2NavigationCompletedEventArgs args)
        {
            var client = new HttpClient();
            var requestUrl = Server_Details.poll_url;
            var token = Server_Details.token;
            var requestData = new StringContent($"token={token}", Encoding.UTF8, "application/x-www-form-urlencoded");
            var response = await client.PostAsync(requestUrl, requestData);
            if (response.IsSuccessStatusCode)
            {
                var response_txt = await response.Content.ReadAsStringAsync();
                Newtonsoft.Json.JsonSerializer jsonSerializer = new Newtonsoft.Json.JsonSerializer();
                var st = new StringReader(response_txt);
                Dictionary<string, string> res_disirialized = jsonSerializer.Deserialize(st, typeof(Dictionary<string, string>)) as Dictionary<string, string>;
                Server_Details.server = res_disirialized["server"];
                Server_Details.login_name = res_disirialized["loginName"];
                Server_Details.app_password = res_disirialized["appPassword"];
                sender.Close();
                localSettings.Values["IsNextCloudInitAlready?"] = true.ToString();
                localSettings.Values["NextCloud_server"] = Server_Details.server;
                localSettings.Values["login_name"] = Server_Details.login_name;
                localSettings.Values["app_password"] = Server_Details.app_password;
                putPodcastsOnScreen();
                (sender.DataContext as Frame).Navigate(typeof(MainPage));
                var popup = new ContentDialog()
                {
                    CloseButtonText = "understood",
                    Title = "Starting to sync in all of your podcasts",
                    Content = @"This might take a few minuts, depending on your internet connection.
Please don't close the app."

                };
                App.MainWindow.startTimer();
                await popup.ShowAsync();
            }

        }


        class continueUrlRegestration : ICommand
        {
            public event EventHandler CanExecuteChanged;

            public bool CanExecute(object parameter)
            {
                throw new NotImplementedException();
            }

            public async void Execute(object parameter)
            {
                var textBox = parameter as TextBox;
                var httpClient = new HttpClient();
                httpClient.BaseAddress = new Uri(textBox.Text);
                var res = await httpClient.PostAsync(textBox.Text + "/login/v2", new StringContent(""));
                var res_txt = await res.Content.ReadAsStringAsync();
                Newtonsoft.Json.JsonSerializer jsonSerializer = new Newtonsoft.Json.JsonSerializer();
                var st = new StringReader(res_txt);
                Dictionary<string, object> res_disirialized = jsonSerializer.Deserialize(st, typeof(Dictionary<string, object>)) as Dictionary<string, object>;
                var login_url = res_disirialized["login"] as string;
                localSettings.Values["login_url"] = login_url;
                var token = ((res_disirialized["poll"] as IEnumerable<IEnumerable<object>>).ElementAt(0)).First().ToString();
                var poll_url = ((res_disirialized["poll"] as IEnumerable<IEnumerable<object>>).ElementAt(1)).First().ToString();
                MainPage.Server_Details = new MainPage.loginPageDitales();
                MainPage.Server_Details.login_url = login_url;
                MainPage.Server_Details.poll_url = poll_url;
                MainPage.Server_Details.token = token;
            }
        }

        private async void StackPanel_DoubleTapped(object sender, DoubleTappedRoutedEventArgs e)
        {
            var podcast = (sender as StackPanel).DataContext as Podcast;
            App.MainWindow.WindowTitleText.Name = podcast.Name;
            //ApisodesList.Podcast = podcast;

            //Frame.Navigate(typeof(ApisodesList));
            var showsAndPodcasts = new ObservableCollection<ShowAndPodcast>();
            var Shows = await ShowsDb.get_all_shows_for_Podcast(podcast, 300);
            foreach (var show in Shows)
            {
                if (MainWindow.mediaPlayer_with_poster.ShowLastPlayed != null)
                {
                    if (show.PlayUrl.Equals(MainWindow.mediaPlayer_with_poster.ShowLastPlayed.Show.PlayUrl))
                    {
                        showsAndPodcasts.Add(MainWindow.mediaPlayer_with_poster.ShowLastPlayed);
                    }
                    else
                    {
                        showsAndPodcasts.Add(new ShowAndPodcast() { Podcast = podcast, Show = show });
                    }
                }
                else
                {
                    showsAndPodcasts.Add(new ShowAndPodcast() { Podcast = podcast, Show = show });
                }
            }

            Frame.NavigateToType(typeof(ShowsFeed), showsAndPodcasts, new FrameNavigationOptions() { IsNavigationStackEnabled = false });
            Frame.Navigate(typeof(ShowsFeed), showsAndPodcasts);
        }

        private async void refresh_button_Click(object sender, RoutedEventArgs e)
        {
            await refesh();
        }
        public async Task refesh()
        {
            update_loading_ring.IsActive = true;
            await Task.Run(() => pull_new_info_about_podcast_put_on_file(Podcasts));
            var Podcastss = await Task.Run(use_cashed_podcasts_and_put_them_on_screen);
            await Sync.SyncService.get_actions_and_put_them_on_file();
            Podcasts.Clear();
            Podcasts_Grid.ItemsSource = Podcasts;
            foreach (var item in Podcastss)
            {
                Podcasts.Add(item);
            }
            update_loading_ring.IsActive = false;
        }
        private static async Task<List<ShowAndPodcast>> getRange(int pageIndex, int pageSize)
        {
            var a = await ShowsDb.get_all_shows(pageSize, pageSize* pageIndex);
                    
                    var podArr = new Podcast[Podcasts.Max((pod) => pod.ID) + 1];
        var showsAndPodcasts = new List<ShowAndPodcast>();
                    foreach (var pod in Podcasts)
                    {
                        podArr[pod.ID] = pod;
                    }
                    foreach (var show in a)
                    {
                        showsAndPodcasts.Add(new ShowAndPodcast() { Podcast = podArr[show.PodcastID], Show = show });
                    }
            return showsAndPodcasts;
        }
        public class ShowsList : IIncrementalSource<ShowAndPodcast>
        {
            public ObservableCollection<ShowAndPodcast> Shows = new ObservableCollection<ShowAndPodcast>();

            public async Task<IEnumerable<ShowAndPodcast>> GetPagedItemsAsync(int pageIndex, int pageSize, CancellationToken cancellationToken = default)
            {
                var show = MainWindow.mediaPlayer_with_poster.ShowLastPlayed;
                var a = await getRange(pageSize, pageSize);
                
                if(show != null)
                {
                    var cont = a.Where((podshow) => podshow.Show.PlayUrl.Equals(show.Show.PlayUrl));
                    if(cont.Count() > 0)
                    {
                        var index = a.IndexOf(cont.FirstOrDefault());
                        
                        a[index] = show;
                    }
                }
                return a.AsEnumerable();
            }
        }
        private async void goto_feed_Click(object sender, RoutedEventArgs e)
        {
            App.MainWindow.WindowTitleText.Name = "Podcasts Feed";
            //var collection = new IncrementalLoadingCollection<ShowsList, ShowAndPodcast>(itemsPerPage:5);

            var showsAndPodcasts = new ObservableCollection<ShowAndPodcast>();
            //foreach(var pod in Podcasts)
            //{
            //    var shows = await ShowsDb.get_all_shows_for_Podcast(pod);
            //    foreach(var show in shows)
            //    {
            //        showsAndPodcasts.Add(new ShowAndPodcast() { Podcast = pod, Show = show});
            //    }
            //}
            var shows = await ShowsDb.get_all_shows(300);
            var podArr = new Podcast[Podcasts.Max((pod) => pod.ID) + 1];
            foreach (var pod in Podcasts)
            {
                podArr[pod.ID] = pod;
            }
            foreach (var show in shows)
            {
                showsAndPodcasts.Add(new ShowAndPodcast() { Podcast = podArr[show.PodcastID], Show = show });
            }

            Frame.Navigate(typeof(ShowsFeed), showsAndPodcasts);
        }
        protected override void OnNavigatedTo(NavigationEventArgs e)
        {
           App.MainWindow.WindowTitleText.Name = "Home Page";
        }

        private async void addPodcast_Click(object sender, RoutedEventArgs e)
        {
            var Textb = new TextBox() { PlaceholderText = "the rss feed url" };
            var parm = new List<object>();
            parm.Add(Textb);
            var popup = new ContentDialog()
            {
                Title = "Write Here The Url Of The Podcast's Rss Feed",
                CloseButtonText = "cancel",
                Content = Textb,
                SecondaryButtonText = "add",
                SecondaryButtonCommandParameter = parm,
                SecondaryButtonCommand = new add(),


            };
            popup.DataContext = false;
            popup.SecondaryButtonClick += Popup_SecondaryButtonClick;
            var res = await popup.ShowAsync();
            if (Textb.Text != "" && Textb.Text != null && ((bool)popup.DataContext))
            {
                (parm[1] as Task).Wait();
                await refesh();
            }
        }

        private void Popup_SecondaryButtonClick(ContentDialog sender, ContentDialogButtonClickEventArgs args)
        {
            sender.DataContext = true;
        }

        class add : ICommand
        {
            public event EventHandler CanExecuteChanged;

            public bool CanExecute(object parameter)
            {
                throw new NotImplementedException();
            }

            public void Execute(object parameter)
            {
                var lsobj = parameter as List<object>;
                var url = (lsobj[0] as TextBox).Text;
                lsobj.Add(Task.Run(async () => await Sync.SyncService.add_or_remove_podcast(url, "add")));
            }
        }

        private void StackPanel_RightTapped(object sender, RightTappedRoutedEventArgs e)
        {
            Podcasts_Grid.SelectedItem = (sender as StackPanel).DataContext as Podcast;
            var contextMenu = new MenuFlyout();
            var del = new MenuFlyoutItem()
            {
                Text = "Remove",
                Icon = new SymbolIcon(Symbol.Delete)
                ,
                DataContext = (sender as StackPanel).DataContext as Podcast
            };
            del.Click += Delete_Click;
            contextMenu.Items.Add(del);
            contextMenu.ShowAt((sender as StackPanel), e.GetPosition((sender as StackPanel)));
        }

        private async void Delete_Click(object sender, RoutedEventArgs e)
        {
            var send = sender as MenuFlyoutItem;
            var podcast = send.DataContext as Podcast;
            if (await Sync.SyncService.add_or_remove_podcast(podcast.Rss_url, "delete"))
            {
                Podcasts.Remove(podcast);
                await refesh();

            }
            else
            {
                var cont = new ContentDialog()
                {
                    Title = "Operation Failed",
                    CloseButtonText = "ok"
                };
                await cont.ShowAsync();
            }
        }
    }
}
namespace PodMerForWinUi
{
    public class ShowAndPodcast
    {
        private PodcastApesode show;
        private Podcast podcast;

        public PodcastApesode Show { get => show; set => show = value; }
        public Podcast Podcast { get => podcast; set => podcast = value; }
    }
}
