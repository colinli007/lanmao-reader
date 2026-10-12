import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Base64;
import java.util.List;

// 每行一个用例：base64(基准地址) \t base64(相对地址)
// 输出每行：base64(结果)，照 MD3 的 NetworkUtils.getAbsoluteURL(String, String)
public class UrlOracle {
    public static void main(String[] args) throws Exception {
        List<String> out = new ArrayList<>();
        for (String line : Files.readAllLines(Path.of(args[0]))) {
            if (line.isEmpty()) continue;
            String[] f = line.split("\t", -1);
            String result = getAbsoluteURL(dec(f[0]), dec(f[1]));
            out.add(Base64.getEncoder().encodeToString(result.getBytes(StandardCharsets.UTF_8)));
        }
        Files.write(Path.of(args[1]), out);
    }

    static String getAbsoluteURL(String baseURL, String relativePath) {
        if (baseURL == null || baseURL.isEmpty()) return relativePath.trim();
        URL absoluteUrl = null;
        try {
            int comma = baseURL.indexOf(',');
            absoluteUrl = new URL(comma < 0 ? baseURL : baseURL.substring(0, comma));
        } catch (Exception e) {
        }
        return getAbsoluteURL(absoluteUrl, relativePath);
    }

    static String getAbsoluteURL(URL baseURL, String relativePath) {
        String relativePathTrim = relativePath.trim();
        if (baseURL == null) return relativePathTrim;
        String lower = relativePathTrim.toLowerCase();
        if (lower.startsWith("http://") || lower.startsWith("https://")) return relativePathTrim;
        if (relativePathTrim.matches("^data:.*?;base64,(.*)")) return relativePathTrim;
        if (relativePathTrim.startsWith("javascript")) return "";
        String relativeUrl = relativePathTrim;
        try {
            return new URL(baseURL, relativePath).toString();
        } catch (Exception e) {
        }
        return relativeUrl;
    }

    static String dec(String s) {
        return new String(Base64.getDecoder().decode(s), StandardCharsets.UTF_8);
    }
}
