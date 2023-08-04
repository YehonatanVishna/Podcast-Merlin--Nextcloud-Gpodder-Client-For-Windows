// Copyright (c) Microsoft Corporation and Contributors.
// Licensed under the MIT License.

using CommunityToolkit.Mvvm.ComponentModel;
using Podcast_Merlin_Uwp;
using PodMerForWinUi.costom_controls;
using System;
using System.Linq;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Threading.Tasks;
//using Windows.UI.Shell;
using Windows.ApplicationModel.Core;
using Windows.UI.Core;
using Windows.UI.ViewManagement;
using Windows.UI.WindowManagement;
using Windows.UI.Xaml;
using Windows.UI.Xaml.Controls;
using Windows.UI.Xaml.Media;

// To learn more about WinUI, the WinUI project structure,
// and more about our project templates, see: http://aka.ms/winui-project-info.

namespace PodMerForWinUi
{
    /// <summary>
    /// An empty window that can be used on its own or navigated to within a Frame.
    /// </summary>
    public sealed partial class MainWindow : Page
    {
        public static Frame frame;
        private static MediaPlayerElement mediaPlayer;
        public static costom_controls.MediaPlayerWithPoster mediaPlayer_with_poster;
        private static Grid mainGridStatic;
        public static Windows.Storage.ApplicationDataContainer localSettings =
Windows.Storage.ApplicationData.Current.LocalSettings;
        public static Windows.Storage.StorageFolder localFolder =
            Windows.Storage.ApplicationData.Current.LocalFolder;
        public class WindowTitle : ObservableObject
        {
            private string name;

            public string Name
            {
                get => name;
                set => SetProperty(ref name, value);
            }
        }
        public class boolObservable : ObservableObject
        {
            private bool booly;

            public bool Booly
            {
                get => booly;
                set => SetProperty(ref booly, value);
            }
        }
        public static boolObservable isDisconnected = new boolObservable() { Booly = false };
        public static MainPage mainPage;
        public static CoreDispatcher dispatcher;
        public ApplicationViewTitleBar titleBar1;
        public MainWindow()
        {
            Task.Run(async () =>
            {
                await new Sql.SqlLite.SqlLiteActions().init();
                await new Sql.SqlLite.SqlLitePodcasts().init();
                await new Sql.SqlLite.SqlLitePodcastsShows().initAsync();
            }).Wait();
            this.InitializeComponent();
            App.MainWindow = this;
            titleBar1 = ApplicationView.GetForCurrentView().TitleBar;

            titleBar1.BackgroundColor = (Application.Current.Resources["AppBarBackgroundThemeBrush"] as SolidColorBrush).Color;
            titleBar1.InactiveBackgroundColor = (Application.Current.Resources["AppBarBackgroundThemeBrush"] as SolidColorBrush).Color;
            titleBar1.ButtonBackgroundColor = (Application.Current.Resources["AppBarBackgroundThemeBrush"] as SolidColorBrush).Color;
            titleBar1.ButtonInactiveBackgroundColor = (Application.Current.Resources["AppBarBackgroundThemeBrush"] as SolidColorBrush).Color;
            var coreTitleBar = CoreApplication.GetCurrentView().TitleBar;
            
            coreTitleBar.ExtendViewIntoTitleBar = true;
            this.ActualThemeChanged += MainWindow_ActualThemeChanged ;
            fff.Navigated += Fff_Navigated;
            dispatcher = this.Dispatcher;
            // Set XAML element as a drag region.
            Window.Current.SetTitleBar(draggable_bar);
            windowTitle.DataContext = this;
            frame = fff;
            mainGridStatic = mainGrid;
            MediaPlayer = poster_player.Player;
            mediaPlayer_with_poster = poster_player;
            Window.Current.Activate();
            Window.Current.CoreWindow.PointerPressed += mouseButtonsHandler; ;
            fff.Navigate(typeof(MainPage));
            if (MainPage.Server_Details != null)
            {
                var credentials = new AuthenticationHeaderValue("Basic", Convert.ToBase64String(Encoding.ASCII.GetBytes($"{MainPage.Server_Details.login_name}:{MainPage.Server_Details.app_password}")));
                client_for_nextcloud.DefaultRequestHeaders.Authorization = credentials;
                updateAvalibility();
                startTimer();

            }
            App.MainWindow = this;




        }

        private void MainWindow_ActualThemeChanged(FrameworkElement sender, object args)
        {
            titleBar1.BackgroundColor = (Application.Current.Resources["AppBarBackgroundThemeBrush"] as SolidColorBrush).Color;
            titleBar1.InactiveBackgroundColor = (Application.Current.Resources["AppBarBackgroundThemeBrush"] as SolidColorBrush).Color;
            titleBar1.ButtonBackgroundColor = (Application.Current.Resources["AppBarBackgroundThemeBrush"] as SolidColorBrush).Color;
            titleBar1.ButtonInactiveBackgroundColor = (Application.Current.Resources["AppBarBackgroundThemeBrush"] as SolidColorBrush).Color;
        }

        private void Fff_Navigated(object sender, Windows.UI.Xaml.Navigation.NavigationEventArgs e)
        {
            if (fff.CanGoBack)
            {
                //Window_title_bar.ColumnDefinitions[0].Width = new GridLength(40);
                back_btn.Visibility = Visibility.Visible;
            }
            else
            {
                //Window_title_bar.ColumnDefinitions[0].Width = new GridLength(0);
                back_btn.Visibility = Visibility.Collapsed;
            }

        }

        protected override void OnNavigatedTo(Windows.UI.Xaml.Navigation.NavigationEventArgs args)
        {
            var a = args.Content;
        }
        public void startTimer()
        {
            var timer = new DispatcherTimer();
            timer.Interval = new TimeSpan(0, 0, 15);
            timer.Tick += Timer_Tick;
            timer.Start();
        }

        private async void Timer_Tick(object sender, object e)
        {
            var lastIsDiscon = isDisconnected.Booly;
            isDisconnected.Booly = !await Sync.SyncService.is_connected_to_users_server();
            if (lastIsDiscon == true && isDisconnected.Booly == false)
            {
                Task.Run(async () =>
                {
                    if (localSettings.Values["are_there_subscription_changes_to_send"] != null && bool.Parse(localSettings.Values["are_there_subscription_changes_to_send"].ToString()))
                    {
                        await Task.Run(() => Sync.SyncService.sendPendingSubs());
                    }
                    if (localSettings.Values["is_there_actions_to_send"] != null && bool.Parse(localSettings.Values["is_there_actions_to_send"].ToString()))
                    {
                        await Task.Run(() => Sync.SyncService.SendEnqueuedActions());
                    }
                    dispatcher.RunAsync(
                    CoreDispatcherPriority.High,
                    () =>
                    {
                        mainPage.refesh();
                    }
                    );
                }
                );
            }
        }
        public async Task updateAvalibility()
        {
            App.MainWindow = this;
            isDisconnected.Booly = !await Sync.SyncService.is_connected_to_users_server();
            if (!isDisconnected.Booly)
            {
                Task.Run(async () =>
                {
                    if (localSettings.Values["are_there_subscription_changes_to_send"] != null && bool.Parse(localSettings.Values["are_there_subscription_changes_to_send"].ToString()))
                    {
                        await Task.Run(() => Sync.SyncService.sendPendingSubs());
                    }
                    if (localSettings.Values["is_there_actions_to_send"] != null && bool.Parse(localSettings.Values["is_there_actions_to_send"].ToString()))
                    {
                        await Task.Run(() => Sync.SyncService.SendEnqueuedActions());
                    }

                    Dispatcher.RunAsync(
                    CoreDispatcherPriority.High,
                    () =>
                    {
                        if(localSettings.Values["HasDoenInitialDown"]!=null && localSettings.Values["HasDoenInitialDown"].ToString().Equals(true.ToString()))
                            mainPage.refesh();
                    }
                    );
                }
                );
            }

        }
        private void mouseButtonsHandler(Windows.UI.Core.CoreWindow sender, Windows.UI.Core.PointerEventArgs args)
        {
            if (args.CurrentPoint.Properties.IsXButton1Pressed)
            {
                if (fff.CanGoBack)
                {
                    fff.GoBack();
                }
            }
            else
            {
                if (args.CurrentPoint.Properties.IsXButton2Pressed)
                {
                    if (fff.CanGoForward)
                    {
                        fff.GoForward();
                    }
                }
            }
        }

        private WindowTitle windowTitleText = new WindowTitle() { Name = "Home page" };
        public static void expendPlayer()
        {
            mainGridStatic.RowDefinitions.Last().Height = new GridLength(150, GridUnitType.Pixel);
        }

        public static HttpClient client_for_nextcloud = new HttpClient();

        public static MediaPlayerElement MediaPlayer { get { return mediaPlayer; } set => mediaPlayer = value; }

        public WindowTitle WindowTitleText
        {
            get => windowTitleText; set
            {
                windowTitleText = value;
            }
        }


        private void back_btn_Click(object sender, RoutedEventArgs e)
        {
            if (fff.CanGoBack)
            {
                fff.GoBack();
            }
        }
    }
}
