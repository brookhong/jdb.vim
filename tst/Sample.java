import java.text.SimpleDateFormat;
import java.text.DateFormat;
import java.util.TimeZone;
import java.util.Date;
import java.util.List;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.concurrent.ThreadLocalRandom;
import java.util.regex.Pattern;
import java.util.regex.Matcher;
import java.util.Calendar;

public class Sample {
    public void doWork() {
        InnerObject o = new InnerObject();
        o.doSomething("job1");
    }

    public static void main(String[] args) {

        SimpleDateFormat dateFormat = new SimpleDateFormat();
        // println TimeZone.getAvailableIDs()
        dateFormat.setTimeZone(TimeZone.getTimeZone("America/Phoenix"));
        java.util.Calendar cal = java.util.Calendar.getInstance();

        System.out.println(dateFormat.format( cal.getTime()));

        List<Integer> lst1 = new ArrayList<Integer>();
        lst1.add(1);
        lst1.add(2);
        List<Integer> lst2 = new ArrayList<Integer>();
        lst2.add(1);
        lst2.add(2);

        System.out.println(lst1 == lst2); // return true in Groovy, false in Java.
        System.out.println(lst1.equals(lst2)); // return true in both Groovy and Java.

        System.out.println(lst1);
        Integer i = 34;
        System.out.println(new ArrayList<Integer>(Arrays.asList(i)));
        Sample a = new Sample();
        a.doWork();

        String subjectString    = "\"sortedDealIDs\" : [\n\"b85bd88d\", \n\"83e03cb4\",  \n\"088d24a6\"],[\n\"b85bd88d\", \n\"83e03cb4\",  \n\"088d24a6\"],";
        Pattern regex = Pattern.compile("^\"sortedDealIDs\" : \\[\\s+([^\\]]*)\\],", Pattern.DOTALL);
        Matcher regexMatcher = regex.matcher(subjectString);
        System.out.println(subjectString);
        System.out.println(subjectString.indexOf("sortedDealIDs"));
        if (regexMatcher.find()) {
            String s = Pattern.compile("[\"\\s]").matcher(regexMatcher.group(1)).replaceAll("");
            System.out.println(s);
            s = Pattern.compile(",").matcher(s).replaceAll("\"}, {\"dealID\":\"");
            s = String.format("{\"dealID\":\"%s\"}", s);
            System.out.println(s);
        }

        // https://www.amazon.cn/xa/dealcontent/v2/GetDealStatus?nocache=1510502855542
        System.out.println("https://www.amazon.cn/xa/dealcontent/v2/GetDealStatus?nocache=" + new Date().getTime());

        System.out.println(Pattern.compile("^gl_").matcher("gl_sports").replaceAll(""));

        String[] aa = new String[]{"a", "b"};
        System.out.println(aa);

        int randomNum = ThreadLocalRandom.current().nextInt(1, 101);
        System.out.println(randomNum);

        Date dt = new Date();
        Calendar rightNow = Calendar.getInstance();
        int round = rightNow.get(Calendar.HOUR_OF_DAY)/3;

        DateFormat df = new SimpleDateFormat("MM/dd/yyyy HH:mm:ss");

        String s = String.format("%s %d:00:00", df.format(dt).substring(0, 10), round*3);
        try {
            Date startDate = df.parse(s);
            System.out.println(s);
            System.out.println(startDate);
        } catch (Exception e) {
            System.out.println(e);
        }
        System.out.println(!"N".equals("N"));
    }

    class InnerObject {
        public void doSomething(String something) {
            System.out.println(something);
        }
    }
}
