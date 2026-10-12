import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Base64;
import java.util.List;

import org.jsoup.Jsoup;
import org.jsoup.nodes.Document;
import org.jsoup.nodes.Element;
import org.jsoup.nodes.TextNode;
import org.jsoup.select.Collector;
import org.jsoup.select.Elements;
import org.jsoup.select.Evaluator;

// 每行一个用例：op \t base64(ctx) \t base64(arg) \t base64(html)
// 输出每行：base64(结果项用 \u0001 连接)，出错时输出 "ERR " + 异常类名
public class Oracle {
    public static void main(String[] args) throws Exception {
        List<String> out = new ArrayList<>();
        for (String line : Files.readAllLines(Path.of(args[0]))) {
            if (line.isEmpty()) continue;
            String[] f = line.split("\t", -1);
            String op = f[0], ctx = dec(f[1]), arg = dec(f[2]), html = dec(f[3]);
            try {
                Document doc = Jsoup.parse(html);
                Element root = ctx.isEmpty() ? doc : doc.selectFirst(ctx);
                List<String> items = new ArrayList<>();
                Elements all = doc.getAllElements();
                switch (op) {
                    case "text": for (Element e : root.select(arg)) items.add(e.text()); break;
                    case "ownText": for (Element e : root.select(arg)) items.add(e.ownText()); break;
                    case "textNodes":
                        for (Element e : root.select(arg)) {
                            List<String> t = new ArrayList<>();
                            for (TextNode n : e.textNodes()) t.add(n.text());
                            items.add(String.join("\u0002", t));
                        }
                        break;
                    case "outerHtml": items.add(root.select(arg).outerHtml()); break;
                    case "data": for (Element e : root.select(arg)) items.add(e.data()); break;
                    case "select": for (Element e : root.select(arg)) items.add(Integer.toString(all.indexOf(e))); break;
                    case "byClass": for (Element e : root.getElementsByClass(arg)) items.add(Integer.toString(all.indexOf(e))); break;
                    case "byTag": for (Element e : root.getElementsByTag(arg)) items.add(Integer.toString(all.indexOf(e))); break;
                    case "byId": for (Element e : Collector.collect(new Evaluator.Id(arg), root)) items.add(Integer.toString(all.indexOf(e))); break;
                    case "ownTextContains": for (Element e : root.getElementsContainingOwnText(arg)) items.add(Integer.toString(all.indexOf(e))); break;
                    case "attr": for (Element e : root.select("*")) items.add(e.attr(arg)); break;
                    default: throw new IllegalArgumentException(op);
                }
                out.add(Base64.getEncoder().encodeToString((items.size() + "\u0003" + String.join("\u0001", items)).getBytes(StandardCharsets.UTF_8)));
            } catch (Exception e) {
                out.add("ERR " + e.getClass().getSimpleName());
            }
        }
        Files.write(Path.of(args[1]), out);
    }

    static String dec(String s) {
        return new String(Base64.getDecoder().decode(s), StandardCharsets.UTF_8);
    }
}
