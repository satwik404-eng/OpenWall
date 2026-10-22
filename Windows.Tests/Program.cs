using OpenWall.Windows;
var temp = Path.Combine(Path.GetTempPath(), "openwall-tests-" + Guid.NewGuid());
double clock = 0;
var file = Path.Combine(temp, "library.json");
var m = new PlaylistModel(file, () => clock);
void Check(bool test, string message) { if (!test) throw new Exception(message); Console.WriteLine("PASS " + message); }
string[] screens = ["main", "other"];
Check(PlaylistModel.Durations.SequenceEqual(new[] { 86400,21600,10800,3600,1800,300,0 }), "All seven requested durations");
Check(m.Wallpapers.Count() == 9 && m.Wallpapers.Select(w => w.Id).Distinct().Count() == 9, "Nine unique original motion wallpapers");
m.Add("aurora"); m.Add("dusk"); m.Add("aurora");
Check(m.State.Playlist.Count == 2, "Playlist prevents duplicates");
var a = m.State.Playlist[0].Id; var b = m.State.Playlist[1].Id;
m.SetDuration(a, 300); m.SetDuration(b, 0); m.Apply("aurora", screens); m.Anchor(screens);
Check(m.State.Assignments.Values.All(id => id == "aurora"), "Click applies immediately to both displays");
clock = 100; m.SetPaused(true, screens); clock = 900; m.Tick(screens);
Check(m.State.Playback["main"].Remaining == 200, "Pause freezes countdown");
m.SetPaused(false, screens); clock = 1101; m.Tick(screens);
Check(m.State.Assignments["main"] == "dusk" && m.State.Playback["main"].Remaining == null, "Expiry advances to Forever");
clock = 999999; m.Tick(screens); Check(m.State.Assignments["main"] == "dusk", "Forever never advances automatically");
m.Next("main"); Check(m.State.Assignments["main"] == "aurora", "Next wraps in order");
m.Move(b, -1); Check(m.State.Playlist[0].Id == b, "Reordering updates playlist");
m.Apply("ember", ["main"]); Check(!m.State.Playback.ContainsKey("main") && m.State.Playback.ContainsKey("other"), "Click outside playlist stops rotation only on target display");
m.RemoveEntry(b); Check(m.State.Assignments["other"] == "aurora", "Removing active entry advances to next");
m.Apply("aurora", ["main"]); m.Anchor(screens); clock += 15; m.Checkpoint(); m.Save();
var saved = new PlaylistModel(file); Check(saved.State.Playback["main"].Remaining == 285, "Remaining time persists");
m.SetDuration(a, 0); Check(m.State.Playback["main"].Remaining == null, "Duration changes affect active playback");
try { m.SetDuration(a, 123); throw new Exception("Invalid duration accepted"); } catch (InvalidOperationException) { Console.WriteLine("PASS Invalid durations rejected"); }
Directory.Delete(temp, true);
Console.WriteLine("All Windows playlist model checks passed.");
