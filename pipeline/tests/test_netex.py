import gzip
import io
import sys
import unittest
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "stages"))
from netex import _secs, convert, nice, route_key  # noqa: E402

DOC = """<?xml version="1.0"?>
<PublicationDelivery xmlns="http://www.netex.org.uk/netex"><dataObjects><CompositeFrame><frames>
<ServiceCalendarFrame>
  <DayType id="dt1"><properties><PropertyOfDay><DaysOfWeek>Monday Tuesday</DaysOfWeek></PropertyOfDay></properties></DayType>
  <UicOperatingPeriod id="op1"><FromDate>2026-11-02T00:00:00</FromDate><ToDate>2026-11-04T00:00:00</ToDate>
    <ValidDayBits>101</ValidDayBits></UicOperatingPeriod>
  <DayTypeAssignment id="a1"><OperatingPeriodRef ref="op1"/><DayTypeRef ref="dt1"/></DayTypeAssignment>
</ServiceCalendarFrame>
<ServiceFrame>
  <Line id="L1"><Name>Sesto - Rho</Name><TransportMode>metro</TransportMode><PublicCode>M1 A</PublicCode></Line>
  <Line id="L2"><Name>Bus 90</Name><TransportMode>bus</TransportMode><PublicCode>90</PublicCode></Line>
  <ScheduledStopPoint id="s1"><Name>P.TA VENEZIA</Name><Location><Longitude>9.205</Longitude><Latitude>45.474</Latitude></Location></ScheduledStopPoint>
  <ScheduledStopPoint id="s2"><Name>CENTRALE FS</Name><Location><Longitude>9.204</Longitude><Latitude>45.486</Latitude></Location></ScheduledStopPoint>
  <ServiceJourneyPattern id="p1"><RouteView><LineRef ref="L1"/></RouteView><pointsInSequence>
    <StopPointInJourneyPattern id="sp1"><ScheduledStopPointRef ref="s1"/></StopPointInJourneyPattern>
    <StopPointInJourneyPattern id="sp2"><ScheduledStopPointRef ref="s2"/></StopPointInJourneyPattern></pointsInSequence></ServiceJourneyPattern>
  <ServiceJourneyPattern id="p2"><RouteView><LineRef ref="L2"/></RouteView><pointsInSequence>
    <StopPointInJourneyPattern id="sp3"><ScheduledStopPointRef ref="s1"/></StopPointInJourneyPattern>
    <StopPointInJourneyPattern id="sp4"><ScheduledStopPointRef ref="s2"/></StopPointInJourneyPattern></pointsInSequence></ServiceJourneyPattern>
</ServiceFrame>
<TimetableFrame><vehicleJourneys>
  <ServiceJourney id="j1"><Name>101</Name><dayTypes><DayTypeRef ref="dt1"/></dayTypes><ServiceJourneyPatternRef ref="p1"/><passingTimes>
    <TimetabledPassingTime><StopPointInJourneyPatternRef ref="sp1"/><DepartureTime>23:58:00</DepartureTime></TimetabledPassingTime>
    <TimetabledPassingTime><StopPointInJourneyPatternRef ref="sp2"/><ArrivalTime>00:03:00</ArrivalTime><ArrivalDayOffset>1</ArrivalDayOffset></TimetabledPassingTime>
  </passingTimes></ServiceJourney>
  <ServiceJourney id="j2"><dayTypes><DayTypeRef ref="dt1"/></dayTypes><ServiceJourneyPatternRef ref="p2"/><passingTimes>
    <TimetabledPassingTime><StopPointInJourneyPatternRef ref="sp3"/><DepartureTime>08:00:00</DepartureTime></TimetabledPassingTime>
    <TimetabledPassingTime><StopPointInJourneyPatternRef ref="sp4"/><ArrivalTime>08:10:00</ArrivalTime></TimetabledPassingTime>
  </passingTimes></ServiceJourney>
</vehicleJourneys></TimetableFrame>
</frames></CompositeFrame></dataObjects></PublicationDelivery>"""


def read(z, name):
    return z.read(name).decode().strip().split("\n")[1:]


class NeTEx(unittest.TestCase):
    def test_metro_journey_becomes_gtfs_buses_dropped(self):
        z = zipfile.ZipFile(io.BytesIO(convert(io.BytesIO(DOC.encode()), {"metro"})))
        self.assertEqual(read(z, "routes.txt"), ["M1,M1,Sesto - Rho,1,"])
        self.assertEqual(read(z, "trips.txt"), ["M1,s1,j1,Centrale FS,101,0"])
        self.assertEqual(read(z, "stop_times.txt"), ["j1,23:58:00,23:58:00,s1,1", "j1,24:03:00,24:03:00,s2,2"])
        self.assertEqual(read(z, "calendar_dates.txt"), ["s1,20261102,1", "s1,20261104,1"])   # the bits, not the weekdays

    def test_times_with_a_zone(self):
        self.assertEqual(_secs("08:15:00+01:00", None), 8 * 3600 + 15 * 60)   # TPER: local clock, suffix dropped
        self.assertEqual(_secs("23:58:30.000", "1"), 24 * 3600 + 23 * 3600 + 58 * 60 + 30)

    def test_names(self):
        self.assertEqual(nice("TORINO PORTA NUOVA"), "Torino Porta Nuova")
        self.assertEqual(nice("STAZIONE DI MILANO-LAMBRATE"), "Stazione di Milano-Lambrate")
        self.assertEqual(nice("Brescia"), "Brescia")
        self.assertEqual(route_key("0083_REG", {}), ("REG", None))
        self.assertEqual(route_key("M4 R", {}), ("M4", 1))
        self.assertEqual(route_key("METRO", {"METRO": "M1"}), ("M1", None))


if __name__ == "__main__":
    unittest.main()
