#!/usr/bin/env python3
"""Validate generated discoverability, assets and repeatable output locally."""
from html.parser import HTMLParser
import json,struct,xml.etree.ElementTree as ET
from site_metadata import ROOT,SITE,ORIGIN,PAGES,generate
class Head(HTMLParser):
 def __init__(self):super().__init__();self.meta={};self.links={};self.json=[];self.in_json=False
 def handle_starttag(self,tag,attrs):
  a=dict(attrs)
  if tag=='meta':self.meta[a.get('name',a.get('property'))]=a.get('content')
  if tag=='link':self.links[a.get('rel')]=a.get('href')
  if tag=='script' and a.get('type')=='application/ld+json':self.in_json=True
 def handle_endtag(self,tag):
  if tag=='script':self.in_json=False
 def handle_data(self,data):
  if self.in_json:self.json.append(json.loads(data))
files=[SITE/(r.lstrip('/') if r.endswith('.html') else r.lstrip('/')+'index.html') for r in PAGES]
before={f:f.read_bytes() for f in files};generate();assert all(f.read_bytes()==b for f,b in before.items()),'Metadata generation must be idempotent'
for route,(_,description,preview,index) in PAGES.items():
 f=SITE/(route.lstrip('/') if route.endswith('.html') else route.lstrip('/')+'index.html');h=Head();h.feed(f.read_text())
 assert h.links['canonical']==ORIGIN+route
 assert h.meta['description']==description and h.meta['og:url']==ORIGIN+route
 assert h.meta['robots']==('index, follow' if index else 'noindex, follow')
 assert h.meta['twitter:card']=='summary_large_image' and h.links['icon']
 assert len(h.json)==1 and h.json[0]['@context']=='https://schema.org'
 assert all('aggregateRating' not in node and 'offers' not in node for node in h.json[0]['@graph'])
 data=(SITE/'assets'/preview).read_bytes();assert data[:8]==b'\x89PNG\r\n\x1a\n' and struct.unpack('>II',data[16:24])==(1200,630)
 assert f.read_text().count('href="/grain.css"')==1
urls=[x.text for x in ET.parse(SITE/'sitemap.xml').getroot().iter('{http://www.sitemaps.org/schemas/sitemap/0.9}loc')]
assert set(urls)=={ORIGIN+r for r,p in PAGES.items() if p[3]}
assert '/extension/dashboard/' not in (SITE/'robots.txt').read_text(),'Allow crawlers to read the dashboard noindex'
for name in ['llms.txt','llms-full.txt']:assert 'developer preview' in (SITE/name).read_text().lower()
print('PASS: five page canonicals, structured data, robots, sitemap, social images, LLM guides and idempotent generation.')
