import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Base64;
import java.util.List;
import org.jsoup.parser.Parser;

// 每行：true/false + TAB + base64(原文)，输出每行 base64(解码结果)。
// javac -cp jsoup-1.16.2.jar EntitiesOracle.java
// java -cp .:jsoup-1.16.2.jar EntitiesOracle input.tsv output.txt
public class EntitiesOracle {
    public static void main(String[] args) throws Exception {
        List<String> out = new ArrayList<>();
        for (String line : Files.readAllLines(Path.of(args[0]))) {
            String[] fields = line.split("\t", -1);
            String text = new String(Base64.getDecoder().decode(fields[1]), StandardCharsets.UTF_8);
            String value = Parser.unescapeEntities(text, Boolean.parseBoolean(fields[0]));
            out.add(Base64.getEncoder().encodeToString(value.getBytes(StandardCharsets.UTF_8)));
        }
        Files.write(Path.of(args[1]), out);
    }
}
