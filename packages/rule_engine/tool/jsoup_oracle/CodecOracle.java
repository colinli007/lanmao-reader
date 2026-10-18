import android.util.Base64;
import java.net.URLEncoder;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Date;
import java.util.List;
import java.util.Locale;
import java.util.SimpleTimeZone;
import javax.crypto.Cipher;
import javax.crypto.Mac;
import javax.crypto.spec.IvParameterSpec;
import javax.crypto.spec.SecretKeySpec;

// 每行一个用例：操作名 \t base64(参数1) \t base64(参数2) ...
// 输出每行：base64(结果)；抛出异常时为 "!" + 异常类名。
// 字节数组一律用小写十六进制表示。
//
// 操作的语义照 MD3（legado-with-MD3 d1b488b）的 JsExtensions / JsEncodeUtils / SymmetricCryptoAndroid，
// 这里只用 JDK、Hutool 和 AOSP 的 android.util.Base64 重新实现，不含 MD3 代码。
public class CodecOracle {
    public static void main(String[] args) throws Exception {
        List<String> out = new ArrayList<>();
        for (String line : Files.readAllLines(Path.of(args[0]))) {
            if (line.isEmpty()) continue;
            String[] f = line.split("\t", -1);
            String[] a = new String[f.length - 1];
            for (int i = 1; i < f.length; i++) a[i - 1] = dec(f[i]);
            String result;
            try {
                result = run(f[0], a);
            } catch (Throwable e) {
                out.add("!" + e.getClass().getSimpleName());
                continue;
            }
            out.add(java.util.Base64.getEncoder().encodeToString(result.getBytes(StandardCharsets.UTF_8)));
        }
        Files.write(Path.of(args[1]), out);
    }

    static String run(String op, String[] a) throws Exception {
        switch (op) {
            // 宽松 Base64：先去掉所有空白，再交给 Hutool
            case "base64Lenient":
                return hex(cn.hutool.core.codec.Base64.decode(a[0].replaceAll("\\s", "")));
            case "base64Decode":
                return hex(Base64.decode(a[0], Integer.parseInt(a[1])));
            case "base64Encode":
                return Base64.encodeToString(unhex(a[0]), Integer.parseInt(a[1]));
            case "strToBytes":
                return hex(a[0].getBytes(Charset.forName(a[1])));
            case "bytesToStr":
                return new String(unhex(a[0]), Charset.forName(a[1]));
            case "encodeURI":
                try {
                    return URLEncoder.encode(a[0], a[1]);
                } catch (Exception e) {
                    return "";
                }
            case "digest":
                return hex(MessageDigest.getInstance(a[0]).digest(a[1].getBytes(StandardCharsets.UTF_8)));
            case "hmac": {
                Mac mac = Mac.getInstance(a[0]);
                mac.init(new SecretKeySpec(a[1].getBytes(StandardCharsets.UTF_8), a[0]));
                return hex(mac.doFinal(a[2].getBytes(StandardCharsets.UTF_8)));
            }
            // 参数：变换、密钥（hex）、IV（hex，空串表示没有）、encrypt 或 decrypt、数据（hex）
            case "cipher":
                return hex(cipher(a[0], unhex(a[1]), a[2].isEmpty() ? null : unhex(a[2]), a[3].equals("encrypt"),
                        unhex(a[4])));
            // 参数：毫秒、格式、时区偏移（毫秒）；Locale 用简体中文（中文设备的默认值）
            case "timeFormatUTC": {
                SimpleDateFormat format = new SimpleDateFormat(a[1], Locale.SIMPLIFIED_CHINESE);
                format.setTimeZone(new SimpleTimeZone(Integer.parseInt(a[2]), "UTC"));
                return format.format(new Date(Long.parseLong(a[0])));
            }
            default:
                throw new IllegalArgumentException(op);
        }
    }

    // createSymmetricCrypto 的语义：变换里没有 "/" 时补成 ECB/PKCS5Padding；DES 密钥超过 8 字节截到 8，
    // DESede 超过 24 字节截到 24（16 字节按 Android 的两段密钥 K1K2K1 处理）；ECB 或没有 IV 时不带 IV
    static byte[] cipher(String algorithm, byte[] key, byte[] iv, boolean encrypt, byte[] data) throws Exception {
        String transformation = algorithm.contains("/") ? algorithm : algorithm + "/ECB/PKCS5Padding";
        // Android 的提供者把 PKCS7Padding 当作 PKCS5Padding，JDK 不认这个名字
        transformation = transformation.replaceAll("(?i)PKCS7Padding", "PKCS5Padding");
        String keyAlgorithm = algorithm.split("/")[0];
        if (keyAlgorithm.equalsIgnoreCase("DES") && key.length > 8) key = Arrays.copyOf(key, 8);
        if (keyAlgorithm.equalsIgnoreCase("DESede") && key.length > 24) key = Arrays.copyOf(key, 24);
        if (keyAlgorithm.equalsIgnoreCase("DESede") && key.length == 16) {
            byte[] full = Arrays.copyOf(key, 24);
            System.arraycopy(key, 0, full, 16, 8);
            key = full;
        }
        Cipher cipher = Cipher.getInstance(transformation);
        int mode = encrypt ? Cipher.ENCRYPT_MODE : Cipher.DECRYPT_MODE;
        SecretKeySpec spec = new SecretKeySpec(key, keyAlgorithm);
        if (iv == null || transformation.toUpperCase(Locale.ROOT).contains("/ECB/")) {
            cipher.init(mode, spec);
        } else {
            cipher.init(mode, spec, new IvParameterSpec(iv));
        }
        return cipher.doFinal(data);
    }

    static String hex(byte[] bytes) {
        StringBuilder sb = new StringBuilder();
        for (byte b : bytes) sb.append(String.format("%02x", b & 0xff));
        return sb.toString();
    }

    static byte[] unhex(String s) {
        byte[] out = new byte[s.length() / 2];
        for (int i = 0; i < out.length; i++) out[i] = (byte) Integer.parseInt(s.substring(2 * i, 2 * i + 2), 16);
        return out;
    }

    static String dec(String s) {
        return new String(java.util.Base64.getDecoder().decode(s), StandardCharsets.UTF_8);
    }
}
