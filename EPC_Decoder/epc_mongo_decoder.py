#functie om benodigde modules te importeren
from pyepc import decode
import pandas as pd
from pymongo import MongoClient, UpdateOne

client = MongoClient("mongodb+srv://Admin:HnMQArUvjQwmO88p@epcdb.l21az7d.mongodb.net/?retryWrites=true&w=majority")

db = client.get_database('epcdb')
records = db.epcs

#Count the total number of documents
#count_documents = records.count_documents({})
#print (count_documents)

#search db for documents with empty serial
#empty_serials = [list(records.find({'serial': ""}))]

#print(empty_serials )
df = pd.DataFrame(list(records.find({'serial': ""})))
#print(df)
#prints the columns to a list
#print(df.columns.tolist())

#Exit script if df is empty
if df.empty == True:
  print("DF is empty")
  exit()

#lijst gtin en serial gemaakt
#haalt de eerste colom op uit iedere rij en decodeert de epc, dan print van gtin en serienummer
gtin = []
serial = []
ean = []
epcs = [x for x in df['EPC']]
for x in epcs:
  epc = decode(x)
  #print(epc.gtin +';' + epc.serial_number)
  #voegt gedecodeeerde waardes toe aan lijst gtin en lijst serial
  gtin.append(epc.gtin)
  serial.append(epc.serial_number)
  ean.append(epc.gtin)

#haalt de eerst nul weg van gtin om ean te krijgen
ean = [e[1:] for e in ean]

#voegt kolom gtin en serial en ean toe aan dataframe
df['gtin']= gtin
df['serial']= serial
df['ean'] = ean

#hernoem de titels voor het dataframe
df.columns =['_id','EPC','Seen','Date','Time','?','RSSI','gtin','serial','ean']

#verwijder kolom NaN'
#df.pop('NaN')

print(df)
#print(df.columns.tolist())
#print(df.index)

#Update df to mongo db

updates = []
for _, row in df.iterrows():
  updates.append(UpdateOne({'_id': row.get('_id')},{'$set': {'gtin': row.get('gtin')}}, upsert=True))
  updates.append(UpdateOne({'_id': row.get('_id')},{'$set': {'serial': row.get('serial')}}, upsert=True))
  updates.append(UpdateOne({'_id': row.get('_id')},{'$set': {'ean': row.get('ean')}}, upsert=True))
  db.epcs.bulk_write(updates)

print("Gtin, Serial and EPC Decoded")
exit()
