import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Base64;
import java.util.List;

import org.jsoup.Jsoup;
import org.jsoup.nodes.Document;
import org.jsoup.nodes.Element;
import org.jsoup.select.Elements;
import org.seimicrawler.xpath.JXDocument;
import org.seimicrawler.xpath.JXNode;

// 每行一个用例：base64(上下文 CSS 选择器，空表示整个文档) \t base64(XPath) \t base64(HTML)
// 输出每行：base64(项数 \u0003 各项用 \u0001 连接)，出错时输出 "ERR"
// 取值照 MD3 的 AnalyzeByXPath：字符串内容先按 strToJXDocument 处理，各项取 JXNode.asString()
public class XPathOracle {
    public static void main(String[] args) throws Exception {
        List<String> out = new ArrayList<>();
        for (String line : Files.readAllLines(Path.of(args[0]))) {
            if (line.isEmpty()) continue;
            String[] f = line.split("\t", -1);
            String ctx = dec(f[0]), xpath = dec(f[1]), html = dec(f[2]);
            try {
                JXDocument doc;
                if (ctx.isEmpty()) {
                    doc = strToJXDocument(html);
                } else {
                    Document parsed = Jsoup.parse(html);
                    doc = JXDocument.create(new Elements(parsed.selectFirst(ctx)));
                }
                List<String> items = new ArrayList<>();
                for (JXNode node : doc.selN(xpath)) items.add(node.asString());
                String result = items.size() + "\u0003" + String.join("\u0001", items);
                out.add(Base64.getEncoder().encodeToString(result.getBytes(StandardCharsets.UTF_8)));
            } catch (Exception e) {
                out.add("ERR");
            }
        }
        Files.write(Path.of(args[1]), out);
    }

    static JXDocument strToJXDocument(String html) {
        String html1 = html;
        if (html1.endsWith("</td>")) html1 = "<tr>" + html1 + "</tr>";
        if (html1.endsWith("</tr>") || html1.endsWith("</tbody>")) html1 = "<table>" + html1 + "</table>";
        return JXDocument.create(html1);
    }

    static String dec(String s) {
        return new String(Base64.getDecoder().decode(s), StandardCharsets.UTF_8);
    }
}
