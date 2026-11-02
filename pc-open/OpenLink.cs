// Resident listener for RemotePanel. The iPad POSTs {title,url,source} and this opens the URL.
// Build: csc /nologo /target:winexe /utf8 /r:System.Windows.Forms.dll /r:System.Drawing.dll /r:System.Web.Extensions.dll OpenLink.cs
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;

internal static class OpenLink
{
    const int DefaultPort = 8092;
    static readonly object Gate = new object();
    static readonly List<string> Recent = new List<string>();
    static NotifyIcon tray;
    static TcpListener listener;
    static int port = DefaultPort;

    [STAThread]
    static void Main(string[] args)
    {
        for (int i = 0; i < args.Length - 1; i++)
        {
            if (args[i] == "--port") int.TryParse(args[i + 1], out port);
        }
        if (port < 1 || port > 65535) port = DefaultPort;

        bool created;
        using (var mutex = new Mutex(true, "Local\\RemotePanel.OpenLink", out created))
        {
            if (!created)
            {
                MessageBox.Show("开页小程序已经在运行。看任务栏右下角的图标。", "RemotePanel 开页");
                return;
            }
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            try
            {
                listener = new TcpListener(IPAddress.Any, port);
                listener.Start();
            }
            catch (Exception ex)
            {
                MessageBox.Show("8092 端口没能打开：" + ex.Message, "RemotePanel 开页");
                return;
            }
            var thread = new Thread(AcceptLoop);
            thread.IsBackground = true;
            thread.Start();

            tray = new NotifyIcon();
            tray.Icon = MakeIcon();
            tray.Visible = true;
            tray.Text = "RemotePanel 开页  " + port;
            var menu = new ContextMenuStrip();
            menu.Items.Add("正在听 " + port, null, delegate { ShowStatus(); });
            menu.Items.Add("退出", null, delegate { Shutdown(); });
            tray.ContextMenuStrip = menu;
            tray.DoubleClick += delegate { ShowStatus(); };
            tray.ShowBalloonTip(3000, "RemotePanel 开页", "正在听 " + port + "。iPad 点一条内容，这里会打开它的网页。", ToolTipIcon.Info);
            Application.Run();
            GC.KeepAlive(mutex);
        }
    }

    static void Shutdown()
    {
        try { if (listener != null) listener.Stop(); } catch { }
        if (tray != null) { tray.Visible = false; tray.Dispose(); }
        Application.Exit();
    }

    static void AcceptLoop()
    {
        while (true)
        {
            TcpClient client;
            try { client = listener.AcceptTcpClient(); }
            catch { return; }
            var taken = client;
            ThreadPool.QueueUserWorkItem(delegate { Handle(taken); });
        }
    }

    static void Handle(TcpClient client)
    {
        try
        {
            client.ReceiveTimeout = 4000;
            client.SendTimeout = 4000;
            using (client)
            using (var stream = client.GetStream())
            {
                var data = ReadHttp(stream);
                if (data == null) return;
                int he0 = HeaderEnd(data);
                if (he0 < 0) return;
                string head = Encoding.ASCII.GetString(data, 0, he0);
                string[] lines = head.Split(new[] { "\r\n" }, StringSplitOptions.None);
                if (lines.Length == 0) return;
                string[] parts = lines[0].Split(' ');
                if (parts.Length < 2) return;
                string method = parts[0].ToUpperInvariant();
                string target = parts[1];
                string path = target;
                string query = "";
                int q = target.IndexOf('?');
                if (q >= 0) { path = target.Substring(0, q); query = target.Substring(q + 1); }
                string body = "";
                int he = HeaderEnd(data);
                if (he >= 0 && he + 4 <= data.Length)
                    body = Encoding.UTF8.GetString(data, he + 4, data.Length - he - 4);

                if (method == "GET" && (path == "/" || path == "/health"))
                {
                    Write(stream, 200, "text/html; charset=utf-8", StatusPage());
                    return;
                }
                string url = "";
                string title = "";
                string source = "";
                if (method == "GET" && path == "/open")
                {
                    url = Query(query, "url");
                    title = Query(query, "title");
                    source = Query(query, "source");
                }
                else if (method == "POST" && (path == "/open" || path == "/"))
                {
                    try
                    {
                        var ser = new JavaScriptSerializer();
                        var map = ser.Deserialize<Dictionary<string, object>>(body ?? "");
                        if (map != null)
                        {
                            if (map.ContainsKey("url") && map["url"] != null) url = map["url"].ToString();
                            if (map.ContainsKey("title") && map["title"] != null) title = map["title"].ToString();
                            if (map.ContainsKey("source") && map["source"] != null) source = map["source"].ToString();
                        }
                    }
                    catch
                    {
                        Write(stream, 400, "application/json; charset=utf-8", "{\"ok\":false,\"error\":\"bad json\"}");
                        return;
                    }
                }
                else
                {
                    Write(stream, 404, "application/json; charset=utf-8", "{\"ok\":false}");
                    return;
                }
                string why;
                if (!Allowed(url, out why))
                {
                    Write(stream, 400, "application/json; charset=utf-8", "{\"ok\":false,\"error\":\"" + Json(why) + "\"}");
                    return;
                }
                Open(url, title, source);
                Write(stream, 200, "application/json; charset=utf-8", "{\"ok\":true}");
            }
        }
        catch { }
    }

    static bool Allowed(string url, out string why)
    {
        why = "";
        if (string.IsNullOrEmpty(url)) { why = "missing url"; return false; }
        if (url.Length > 2000) { why = "url too long"; return false; }
        Uri uri;
        if (!Uri.TryCreate(url, UriKind.Absolute, out uri)) { why = "bad url"; return false; }
        if (uri.Scheme != Uri.UriSchemeHttp && uri.Scheme != Uri.UriSchemeHttps) { why = "only http"; return false; }
        return true;
    }

    static void Open(string url, string title, string source)
    {
        string line = DateTime.Now.ToString("HH:mm:ss") + "  " + (string.IsNullOrEmpty(source) ? "" : source + "  ") + (string.IsNullOrEmpty(title) ? url : title);
        lock (Gate)
        {
            Recent.Insert(0, line);
            while (Recent.Count > 30) Recent.RemoveAt(Recent.Count - 1);
        }
        try
        {
            Process.Start(new ProcessStartInfo { FileName = url, UseShellExecute = true });
        }
        catch (Exception ex)
        {
            lock (Gate) { Recent.Insert(0, "没能打开：" + ex.Message); }
        }
        try
        {
            if (tray != null)
            {
                string tip = string.IsNullOrEmpty(title) ? url : title;
                if (tip.Length > 60) tip = tip.Substring(0, 60);
                tray.ShowBalloonTip(2500, "打开", tip, ToolTipIcon.Info);
            }
        }
        catch { }
    }

    static void ShowStatus()
    {
        string text;
        lock (Gate)
        {
            text = Recent.Count == 0 ? "还没有收到条目。" : string.Join(Environment.NewLine, Recent.ToArray());
        }
        MessageBox.Show("正在听端口 " + port + "。\n\n" + text, "RemotePanel 开页");
    }

    static string StatusPage()
    {
        var sb = new StringBuilder();
        sb.Append("<!doctype html><meta charset=utf-8><title>RemotePanel 开页</title>");
        sb.Append("<body style=\"font-family:sans-serif;background:#10141c;color:#e8eef8;padding:24px\">");
        sb.Append("<h1>开页小程序正在听 ").Append(port).Append("</h1>");
        sb.Append("<p>iPad 点一条内容后，这里会用浏览器打开它。</p><ul>");
        lock (Gate)
        {
            if (Recent.Count == 0) sb.Append("<li>还没有收到条目。</li>");
            foreach (var line in Recent) sb.Append("<li>").Append(WebUtilityHtml(line)).Append("</li>");
        }
        sb.Append("</ul></body>");
        return sb.ToString();
    }

    static string WebUtilityHtml(string s)
    {
        return (s ?? "").Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;");
    }

    static string Json(string s)
    {
        return (s ?? "").Replace("\\", "\\\\").Replace("\"", "\\\"");
    }

    static string Query(string query, string key)
    {
        foreach (var pair in (query ?? "").Split('&'))
        {
            int eq = pair.IndexOf('=');
            if (eq <= 0) continue;
            if (Uri.UnescapeDataString(pair.Substring(0, eq)) != key) continue;
            return Uri.UnescapeDataString(pair.Substring(eq + 1).Replace("+", " "));
        }
        return "";
    }

    static int HeaderEnd(byte[] data)
    {
        for (int i = 0; i + 3 < data.Length; i++)
        {
            if (data[i] == 13 && data[i + 1] == 10 && data[i + 2] == 13 && data[i + 3] == 10) return i;
        }
        return -1;
    }

    static byte[] ReadHttp(NetworkStream stream)
    {
        var ms = new MemoryStream();
        var buf = new byte[4096];
        int headerAt = -1;
        int need = -1;
        while (ms.Length < 1024 * 256)
        {
            int n;
            try { n = stream.Read(buf, 0, buf.Length); }
            catch { return null; }
            if (n <= 0) break;
            ms.Write(buf, 0, n);
            var all = ms.ToArray();
            if (headerAt < 0) headerAt = HeaderEnd(all);
            if (headerAt >= 0 && need < 0)
            {
                string head = Encoding.ASCII.GetString(all, 0, headerAt);
                need = 0;
                foreach (var line in head.Split(new[] { "\r\n" }, StringSplitOptions.None))
                {
                    if (line.StartsWith("Content-Length:", StringComparison.OrdinalIgnoreCase))
                    {
                        int parsed;
                        if (int.TryParse(line.Substring(15).Trim(), out parsed) && parsed > 0) need = parsed;
                    }
                }
            }
            if (headerAt >= 0 && ms.Length >= headerAt + 4 + Math.Max(need, 0)) break;
        }
        return ms.ToArray();
    }

    static void Write(NetworkStream stream, int code, string type, string body)
    {
        byte[] bytes = Encoding.UTF8.GetBytes(body ?? "");
        string reason = code == 200 ? "OK" : code == 400 ? "Bad Request" : "Not Found";
        string head = "HTTP/1.1 " + code + " " + reason + "\r\nContent-Type: " + type +
            "\r\nContent-Length: " + bytes.Length + "\r\nConnection: close\r\nAccess-Control-Allow-Origin: *\r\n\r\n";
        byte[] hb = Encoding.ASCII.GetBytes(head);
        stream.Write(hb, 0, hb.Length);
        stream.Write(bytes, 0, bytes.Length);
    }

    static Icon MakeIcon()
    {
        var bmp = new Bitmap(32, 32);
        using (var g = Graphics.FromImage(bmp))
        {
            g.Clear(Color.FromArgb(16, 20, 28));
            using (var brush = new SolidBrush(Color.FromArgb(46, 140, 255)))
                g.FillEllipse(brush, 2, 2, 28, 28);
            using (var pen = new Pen(Color.White, 3))
            {
                g.DrawLine(pen, 9, 16, 22, 16);
                g.DrawLine(pen, 16, 10, 22, 16);
                g.DrawLine(pen, 16, 22, 22, 16);
            }
        }
        return Icon.FromHandle(bmp.GetHicon());
    }
}
