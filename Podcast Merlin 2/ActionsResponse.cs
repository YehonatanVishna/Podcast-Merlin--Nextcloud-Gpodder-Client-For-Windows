using Newtonsoft.Json;
using System.Collections.Generic;

namespace PodMerForWinUi
{
    public class ActionsResponse
    {
        public int timestamp;
        [JsonProperty("actions")]
        public List<Action> actions;
    }
}
