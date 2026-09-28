"""Deterministic place-name generation per culture (original names, flavoured by language family)."""
import random

POOLS = {
    "germanic": {
        "pre": ["Wald", "Eisen", "Falk", "Rot", "Hoh", "Schwarz", "Brun", "Ald", "Lind", "Stein", "Wolf", "Rab",
                "Tann", "Hel", "Ost", "Gar", "Ber", "Kron", "Dorn", "Eber", "Sig", "Ulm", "Hart", "Meer"],
        "suf": ["burg", "wald", "stein", "feld", "au", "heim", "tal", "berg", "hausen", "furt", "mark", "dorf",
                "brunn", "hof", "wacht", "horst"],
    },
    "latin": {
        "pre": ["Val", "Monte", "Castel", "Borgo", "Rocca", "Pian", "Fonte", "Selva", "Corte", "Ponte", "Riva",
                "Torre", "Colle", "Campo", "Vico", "Prato", "Terra", "Porta", "Villa", "Aqua"],
        "suf": ["bruna", "chiara", "nera", "alta", "vecchia", "fiorita", "dorata", "serena", "antica", "rossa",
                "bianca", "lunga", "verde", "forte", "regia", "santa", "quieta", "ombrosa", "ventosa", "salda"],
    },
    "slavic": {
        "pre": ["Bel", "Vysh", "Dobr", "Mir", "Stary", "Novo", "Zlat", "Krasn", "Vel", "Bor", "Lug", "Tver",
                "Ozer", "Grad", "Sosn", "Yar", "Svet", "Kamen", "Dub", "Vol"],
        "suf": ["grad", "gorod", "ovo", "ets", "sk", "ino", "ava", "ice", "slav", "polye", "gora", "yar", "eva"],
    },
    "hellenic": {
        "pre": ["Theo", "Kal", "Mel", "Arg", "Pyr", "Lyk", "Nik", "Chry", "Aige", "Kory", "Thal", "Doro", "Pel",
                "Elae", "Akr", "Myr", "Xan", "Ser", "Ery", "Kyd"],
        "suf": ["polis", "ia", "os", "oupolis", "ene", "ai", "ikon", "ada", "ousa", "aion", "ethra", "onia",
                "ymna", "asos"],
    },
    "arab": {
        "pre": ["Qal'at ", "Wadi ", "Bir ", "Ras ", "Dar ", "Ain ", "Tell ", "Suq ", "Jabal ", "Bab ", "Madinat ",
                "Qasr "],
        "mid": ["al-"],
        "suf": ["Nahr", "Zahra", "Hamra", "Sabir", "Rimal", "Nujum", "Qamar", "Bayda", "Ward", "Malih", "Hadid",
                "Nakhil", "Sahra", "Faris", "Rawda", "Thalj", "Karim", "Safa"],
    },
    "asian": {
        "pre": ["Chandra", "Deva", "Surya", "Indra", "Ratna", "Hari", "Kanaka", "Padma", "Vira", "Amra", "Megha",
                "Shila", "Nila", "Soma", "Tara", "Gauri"],
        "suf": ["pur", "giri", "nagar", "vati", "kot", "garh", "abad", "vana", "tirtha", "palli", "desha", "kund"],
    },
}


class NameGenerator:
    def __init__(self, seed):
        self.rng = random.Random(seed)
        self.used = set()

    def make(self, culture):
        pool = POOLS.get(culture, POOLS["latin"])
        for _ in range(200):
            if culture == "arab":
                name = self.rng.choice(pool["pre"]) + self.rng.choice(pool["mid"]) + self.rng.choice(pool["suf"])
            else:
                pre = self.rng.choice(pool["pre"])
                suf = self.rng.choice(pool["suf"])
                if culture == "latin" and self.rng.random() < 0.5:
                    name = pre + " " + suf.capitalize() if self.rng.random() < 0.5 else pre + suf
                else:
                    name = pre + suf
                name = name[0].upper() + name[1:]
            if name not in self.used:
                self.used.add(name)
                return name
        name = "%s %d" % (culture.capitalize(), len(self.used))
        self.used.add(name)
        return name

