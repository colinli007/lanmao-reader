import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Base64;
import java.util.List;

import com.jayway.jsonpath.JsonPath;
import com.jayway.jsonpath.ReadContext;

// 每行一个用例：base64(JSON 文档) \t base64(路径)
// 输出每行：base64(确定路径 \u0003 getString 结果 \u0003 getStringList 各项用 \u0001 连接 \u0003 getStringList 项数)
// 取值规则照 MD3 的 AnalyzeByJSonPath：出错时 getString 为空串、getStringList 为空列表
public class JsonPathOracle {
    public static void main(String[] args) throws Exception {
        List<String> out = new ArrayList<>();
        for (String line : Files.readAllLines(Path.of(args[0]))) {
            if (line.isEmpty()) continue;
            String[] f = line.split("\t", -1);
            String doc = dec(f[0]), path = dec(f[1]);
            String definite;
            try {
                definite = Boolean.toString(JsonPath.compile(path).isDefinite());
            } catch (Exception e) {
                definite = "ERR";
            }
            ReadContext ctx = JsonPath.parse(doc);
            String str = "";
            try {
                Object ob = ctx.read(path);
                if (ob instanceof List) {
                    List<String> parts = new ArrayList<>();
                    for (Object o : (List<?>) ob) parts.add(String.valueOf(o));
                    str = String.join("\n", parts);
                } else {
                    str = ob.toString();
                }
            } catch (Exception e) {
                str = "";
            }
            List<String> list = new ArrayList<>();
            try {
                Object obj = ctx.read(path);
                if (obj instanceof List) {
                    for (Object o : (List<?>) obj) list.add(o.toString());
                } else {
                    list.add(obj.toString());
                }
            } catch (Exception e) {
                // MD3 吞掉异常，已经加进去的项保留
            }
            String result = definite + "\u0003" + str + "\u0003" + String.join("\u0001", list) + "\u0003" + list.size();
            out.add(Base64.getEncoder().encodeToString(result.getBytes(StandardCharsets.UTF_8)));
        }
        Files.write(Path.of(args[1]), out);
    }

    static String dec(String s) {
        return new String(Base64.getDecoder().decode(s), StandardCharsets.UTF_8);
    }
}
