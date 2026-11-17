package org.lindbergh.vt3;

import android.util.Log;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.net.URI;
import java.security.SecureRandom;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.TimeUnit;
import javax.net.ssl.HostnameVerifier;
import javax.net.ssl.HttpsURLConnection;
import javax.net.ssl.SSLSocket;
import javax.net.ssl.SSLSocketFactory;

/**
 * One WebSocket for netplay over the Internet (the runtime's netws.c calls
 * these statics through JNI): ws:// or wss:// (TLS, the system's trusted
 * certificates), binary messages only. The runtime polls recv() from its
 * network thread; a reader thread here fills the queue. No library: the
 * handshake and the frames (RFC 6455) are a few lines each.
 */
public final class NetWs {
    private static final String TAG = "NetWs";
    private static volatile int state;          // 0 connecting, 1 open, -1 closed or failed
    private static volatile Socket socket;
    private static OutputStream out;
    private static final ConcurrentLinkedQueue<byte[]> inbox = new ConcurrentLinkedQueue<>();
    /* sends go out on a writer thread: the game thread never waits on the socket */
    private static final LinkedBlockingQueue<byte[]> outbox = new LinkedBlockingQueue<>();
    private static final SecureRandom rnd = new SecureRandom();

    public static void open(final String url) {
        close();
        state = 0;
        inbox.clear();
        Thread t = new Thread(() -> run(url), "netws");
        t.setDaemon(true);
        t.start();
    }
    public static int state() { return state; }
    public static byte[] recv() { return inbox.poll(); }

    public static boolean send(byte[] b) {
        if (state != 1) return false;
        if (outbox.size() > 64) outbox.poll();      /* behind: the oldest goes (each packet repeats the recent inputs) */
        outbox.offer(frame(0x2, b));
        return true;
    }
    private static void writer(Socket s) {
        try {
            while (socket == s && state == 1) {
                byte[] f = outbox.poll(100, TimeUnit.MILLISECONDS);
                if (f == null) continue;
                synchronized (NetWs.class) { out.write(f); }
                if (outbox.isEmpty()) synchronized (NetWs.class) { out.flush(); }
            }
        } catch (Exception e) { fail("send: " + e); }
    }
    public static void close() {
        Socket s = socket; socket = null;
        if (s != null) { try { synchronized (NetWs.class) { if (out != null) out.write(frame(0x8, new byte[0])); } } catch (Exception e) { } try { s.close(); } catch (Exception e) { } }
        state = -1;
    }

    private static void fail(String why) {
        if (state != -1) Log.w(TAG, why);
        state = -1;
        Socket s = socket; socket = null;
        if (s != null) try { s.close(); } catch (Exception e) { }
    }

    private static void run(String url) {
        try {
            URI u = new URI(url);
            boolean tls = "wss".equals(u.getScheme());
            String host = u.getHost();
            int port = u.getPort() > 0 ? u.getPort() : tls ? 443 : 80;
            String path = (u.getRawPath() == null || u.getRawPath().isEmpty() ? "/" : u.getRawPath());
            Socket s;
            if (tls) {
                SSLSocket ss = (SSLSocket) SSLSocketFactory.getDefault().createSocket();
                ss.connect(new InetSocketAddress(host, port), 8000);
                ss.startHandshake();
                HostnameVerifier hv = HttpsURLConnection.getDefaultHostnameVerifier();
                if (!hv.verify(host, ss.getSession())) throw new Exception("certificate is not for " + host);
                s = ss;
            } else {
                s = new Socket();
                s.connect(new InetSocketAddress(host, port), 8000);
            }
            s.setTcpNoDelay(true);
            socket = s;
            byte[] key = new byte[16]; rnd.nextBytes(key);
            String k = android.util.Base64.encodeToString(key, android.util.Base64.NO_WRAP);
            OutputStream o = s.getOutputStream();
            o.write(("GET " + path + " HTTP/1.1\r\nHost: " + host + (u.getPort() > 0 ? ":" + port : "") +
                     "\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: " + k +
                     "\r\nSec-WebSocket-Version: 13\r\nUser-Agent: lindbergh-netplay\r\n\r\n").getBytes("US-ASCII"));
            o.flush();
            InputStream in = s.getInputStream();
            String status = line(in);
            if (status == null || !status.contains(" 101")) throw new Exception("refused: " + status);
            while (true) { String l = line(in); if (l == null) throw new Exception("closed in the handshake"); if (l.isEmpty()) break; }
            synchronized (NetWs.class) { out = new java.io.BufferedOutputStream(o, 8192); }
            outbox.clear();
            state = 1;
            final Socket ws = s;
            Thread w = new Thread(() -> writer(ws), "netws-out"); w.setDaemon(true); w.start();
            Log.i(TAG, "open: " + url);
            ByteArrayOutputStream msg = new ByteArrayOutputStream();
            while (state == 1) {
                int b0 = in.read(), b1 = in.read();
                if (b0 < 0 || b1 < 0) throw new Exception("closed by the server");
                int op = b0 & 0x0f; long n = b1 & 0x7f;
                if (n == 126) n = (in.read() << 8) | in.read();
                else if (n == 127) { n = 0; for (int i = 0; i < 8; i++) n = (n << 8) | in.read(); }
                if (n > 65536) throw new Exception("message too big");
                byte[] mask = null;
                if ((b1 & 0x80) != 0) { mask = new byte[4]; readFully(in, mask); }
                byte[] p = new byte[(int) n]; readFully(in, p);
                if (mask != null) for (int i = 0; i < p.length; i++) p[i] ^= mask[i & 3];
                if (op == 0x8) throw new Exception("closed by the server");
                if (op == 0x9) { outbox.offer(frame(0xA, p)); continue; }
                if (op == 0x2 || op == 0x0) {
                    msg.write(p);
                    if ((b0 & 0x80) != 0) { inbox.add(msg.toByteArray()); msg.reset(); }
                }
            }
        } catch (Exception e) {
            fail("netws: " + e);
        }
    }

    private static String line(InputStream in) throws Exception {
        StringBuilder b = new StringBuilder();
        int c;
        while ((c = in.read()) >= 0) { if (c == '\n') return b.toString().trim(); b.append((char) c); if (b.length() > 4096) return null; }
        return null;
    }
    private static void readFully(InputStream in, byte[] b) throws Exception {
        int k = 0;
        while (k < b.length) { int r = in.read(b, k, b.length - k); if (r < 0) throw new Exception("closed"); k += r; }
    }
    private static byte[] frame(int op, byte[] p) {
        int n = p.length, h = n < 126 ? 2 : n < 65536 ? 4 : 10;
        byte[] f = new byte[h + 4 + n];
        f[0] = (byte) (0x80 | op);
        if (n < 126) f[1] = (byte) (0x80 | n);
        else if (n < 65536) { f[1] = (byte) (0x80 | 126); f[2] = (byte) (n >> 8); f[3] = (byte) n; }
        else { f[1] = (byte) (0x80 | 127); for (int i = 0; i < 8; i++) f[2 + i] = (byte) ((long) n >> (56 - 8 * i)); }
        byte[] m = new byte[4]; rnd.nextBytes(m);
        System.arraycopy(m, 0, f, h, 4);
        for (int i = 0; i < n; i++) f[h + 4 + i] = (byte) (p[i] ^ m[i & 3]);
        return f;
    }
}
