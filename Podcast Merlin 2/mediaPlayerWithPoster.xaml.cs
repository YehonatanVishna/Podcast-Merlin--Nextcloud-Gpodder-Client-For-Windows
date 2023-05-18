// Copyright (c) Microsoft Corporation and Contributors.
// Licensed under the MIT License.

using System;
using Windows.UI.Xaml;
using Windows.UI.Xaml.Controls;
using Windows.UI.Xaml.Media;
using Windows.UI.Xaml.Media.Imaging;

// To learn more about WinUI, the WinUI project structure,
// and more about our project templates, see: http://aka.ms/winui-project-info.

namespace PodMerForWinUi.costom_controls
{

    public sealed partial class MediaPlayerWithPoster : UserControl
    {
        private string imageUrl;
        private string track_name;
        private MediaPlayerElement player;
        private bool isLoaded;
        private bool didContentGetPlayed = false;
        private  ShowAndPodcast showLastPlayed = null;
        public MediaPlayerWithPoster()
        {
            this.InitializeComponent();
            this.DataContext = this;
            player = player_control;
            player.SetMediaPlayer(new Windows.Media.Playback.MediaPlayer());
            player.MediaPlayer.MediaOpened += MediaPlayer_MediaOpened;
            player.DataContextChanged += MediaPlayer_SourceChanged;


        }
        //~MediaPlayerWithPoster()
        //{
        //    if (ShowLastPlayed != null)
        //    {
        //        PodMerForWinUi.Sync.SyncService.SendAction(ShowLastPlayed, ((int)player.MediaPlayer.Position.TotalSeconds)).Wait();
        //    }
        //}

        private void MediaPlayer_SourceChanged(FrameworkElement sender, object args)
        {
            showLastPlayed = sender.DataContext as ShowAndPodcast;
        }

        private void MediaPlayer_MediaOpened(Windows.Media.Playback.MediaPlayer sender, object args)
        {
            didContentGetPlayed = true;
            //Binding myBinding = new Binding();
            //myBinding.Source = sender;
            //myBinding.Path = new PropertyPath("SomeString");
            //myBinding.Mode = BindingMode.TwoWay;
            //myBinding.UpdateSourceTrigger = UpdateSourceTrigger.PropertyChanged;

        }

        public void Initialise_media_player()
        {
            try
            {
                FrameworkElement transportControlsTemplateRoot = (FrameworkElement)VisualTreeHelper.GetChild(MainWindow.MediaPlayer.TransportControls, 0);
                Slider sliderControl = (Slider)transportControlsTemplateRoot.FindName("ProgressSlider");
                //actual_Player_controls.Children.Add(sliderControl);
                sliderControl.MaxHeight = 1000;
                sliderControl.Height = 60;

                sliderControl.Header = Track_name;
                var outerGrid = (((sliderControl.Parent as Grid).Parent as Border).Parent as Grid);
                outerGrid.Height = 150;
                outerGrid.BorderThickness = new Thickness(0, 0, 0, 0);
                MainWindow.expendPlayer();
            }
            catch
            {

            }

        }

        public MediaPlayerElement Player { get { return player; } set => player = value; }
        public string ImageUrl
        {
            get => imageUrl; set
            {
                imageUrl = value;
                poster_img.Source = new BitmapImage(new Uri(imageUrl));
            }
        }

        public string Track_name
        {
            get => track_name; set
            {
                track_name = value;
            }
        }

        public bool IsLoaded1 { get => isLoaded; set => isLoaded = value; }
        public bool DidContentGetPlayed { get => didContentGetPlayed; set => didContentGetPlayed = value; }
        public ShowAndPodcast ShowLastPlayed { get => showLastPlayed; set => showLastPlayed = value; }
    }
}
