import java.text.SimpleDateFormat;
import java.util.TimeZone;
import java.util.List;
import java.util.ArrayList;
import java.util.Arrays;

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
    }

    class InnerObject {
        public void doSomething(String something) {
            System.out.println(something);
        }
    }
}
