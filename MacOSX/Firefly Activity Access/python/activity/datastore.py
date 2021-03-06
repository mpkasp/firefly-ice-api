import datetime
from dateutil import parser
import json
import os
import struct


class HardwareRange:
    def __init__(self, hardware_identifier=None, start=None, end=None):
        self.hardware_identifier = hardware_identifier
        self.start = start
        self.end = end

    def __repr__(self):
        return "HardwareRange(" + repr(self.hardware_identifier) + ", " + repr(self.start) + ", " + repr(self.end) + ")"


class NameRange:
    def __init__(self, name, hardware_ranges):
        self.name = name
        self.hardware_ranges = hardware_ranges

    def __repr__(self):
        return "NameRange(" + repr(self.name) + ", " + repr(self.hardware_ranges) + ")"


class Naming:
    def __init__(self, name, hardware_identifier, start):
        self.name = name
        self.hardware_identifier = hardware_identifier
        self.start = start
        self.hardware_ranges = []


class NameRangeExtractor:
    def __init__(self):
        self.namingByHardwareIdentifier = {}

    def process(self, item):
        type = item['type']
        try:
            method = getattr(self, type)
            method(item)
        except AttributeError:
            pass

    def nameDevice(self, item):
        date = parser.parse(item['date']).timestamp()
        value = item['value']
        name = value['name']
        hardware_identifier = value['hardwareIdentifier']
        naming = self.namingByHardwareIdentifier.get(hardware_identifier)
        if naming is None:
            self.namingByHardwareIdentifier[hardware_identifier] = Naming(name, hardware_identifier, date)
        else:
            if naming.hardware_identifier is None:
                naming.hardware_identifier = hardware_identifier
                naming.start = date
            else:
                if naming.hardware_identifier != hardware_identifier:
                    naming.hardware_ranges.append(HardwareRange(naming.hardware_identifier, naming.start, date))
                    naming.hardware_identifier = hardware_identifier
                    naming.start = date

    def forgetDevice(self, item):
        date = parser.parse(item['date']).timestamp()
        value = item['value']
        name = value['name']
        hardware_identifier = value['hardwareIdentifier']
        naming = self.namingByHardwareIdentifier.get(hardware_identifier)
        if naming is None:
            naming = Naming(name, None, None)
            self.namingByHardwareIdentifier[hardware_identifier] = naming
        naming.hardware_ranges.append(HardwareRange(naming.hardware_identifier, naming.start, date))
        naming.hardware_identifier = None
        naming.start = None

    def name_ranges(self):
        name_ranges = []
        for hardware_identifier, naming in self.namingByHardwareIdentifier.items():
            if naming.start is not None:
                naming.hardware_ranges.append(HardwareRange(naming.hardware_identifier, naming.start, None))
            name_ranges.append(NameRange(naming.name, naming.hardware_ranges))
        return name_ranges


class StudyIdentifierExtractor:
    def __init__(self):
        self.studyIdentifier = None

    def process(self, item):
        type = item['type']
        try:
            method = getattr(self, type)
            method(item)
        except AttributeError:
            pass

    def saveStudy(self, item):
        value = item['value']
        self.studyIdentifier = value['studyIdentifier']


class Datastore:
    def __init__(self, path):
        self.path = path

    def list(self):
        installations = []
        installation_uuids = os.listdir(self.path)
        for installation_uuid in installation_uuids:
            installation_uuid_path = os.path.join(self.path, installation_uuid)
            name_range_extractor = NameRangeExtractor()
            study_identifier_extractor = StudyIdentifierExtractor()
            datastores = os.listdir(installation_uuid_path)
            for datastore in datastores:
                datastore_path = os.path.join(installation_uuid_path, datastore)
                if datastore == 'history':
                    days = sorted(os.listdir(datastore_path))
                    for day in days:
                        day_path = os.path.join(datastore_path, day)
                        with open(day_path) as file:
                            for _, line in enumerate(file):
                                item = json.loads(line)
                                name_range_extractor.process(item)
                                study_identifier_extractor.process(item)
                elif datastore.startswith('FireflyIce-'):
                    pass
            installations.append({
                "installationUUID": installation_uuid,
                "name_ranges": name_range_extractor.name_ranges(),
                'study_identifier': study_identifier_extractor.studyIdentifier
            })
        return installations


class ActivitySpan:
    def __init__(self, time, interval, vmas):
        self.time = time
        self.interval = interval
        self.vmas = vmas

    def __repr__(self):
        return "ActivitySpan(" + repr(self.time) + ", " + repr(self.interval) + ", " + repr(self.vmas) + ")"


class FDBinary:
    def __init__(self, data):
        self.data = data
        self.index = 0

    def get_remaining_length(self):
        return len(self.data) - self.index

    def get_uint32(self):
        value = struct.unpack('<I', self.data[self.index:self.index + 4])[0]
        self.index += 4
        return value

    def get_float32(self):
        value = struct.unpack('<f', self.data[self.index:self.index + 4])[0]
        self.index += 4
        return value


class ActivityDatastore:
    def __init__(self, root, installation_uuid, hardware_identifier):
        self.bytes_per_record = 8
        self.interval = 10
        self.extension = ".dat"
        self.root = root
        self.installation_uuid = installation_uuid
        self.hardware_identifier = hardware_identifier
        self.data = None
        self.start = None
        self.end = None

    def load(self, day):
        start = datetime.datetime.strptime(day + " UTC", "%Y-%m-%d %Z")
        self.start = start.timestamp()
        self.end = (start + datetime.timedelta(days=1)).timestamp()
        path = os.path.join(self.root, self.installation_uuid, self.hardware_identifier, day + self.extension)
        with open(path, "rb") as file:
            self.data = file.read()

    @staticmethod
    def days_in_range(start, end):
        days = []
        start_of_day = datetime.datetime.fromtimestamp(start).replace(hour=0, minute=0, second=0, microsecond=0)
        end_datetime = datetime.datetime.fromtimestamp(end)
        while start_of_day < end_datetime:
            days.append(start_of_day.strftime("%Y-%m-%d"))
            start_of_day += datetime.timedelta(days=1)
        return days

    def query(self, start, end):
        spans = []
        vmas = []
        last_time = 0
        days = ActivityDatastore.days_in_range(start, end)
        for day in days:
            try:
                self.load(day)
            except:
                continue

            time = self.start
            binary = FDBinary(self.data)
            while binary.get_remaining_length() >= self.bytes_per_record:
                flags = binary.get_uint32()
                vma = binary.get_float32()
                if (start < time) and (time < end):
                    valid = flags != 0
                    if valid:
                        if not vmas:
                            last_time = time
                        vmas.append(vma)
                    else:
                        if vmas:
                            spans.append(ActivitySpan(last_time, self.interval, list(vmas)))
                            last_time = 0
                            vmas.clear()
                time += self.interval
        if vmas:
            spans.append(ActivitySpan(last_time, self.interval, vmas))
        return spans

