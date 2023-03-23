from core.models import Note
from rest_framework.views import APIView
from rest_framework.response import Response
from core.serializers import NoteSerializer

class NoteView(APIView):
    
    def get(self,request,format=None):
        uid = request.uid
        notes = Note.objects.filter(uid=uid).all()
        return Response(NoteSerializer(notes,many=True).data)
    
    def put(self,request,pk,format=None):
        data = request.data
        data['uid'] = request.uid
        note,_ = Note.objects.update_or_create(id=pk,defaults=data)
        note.save()
        return Response(NoteSerializer(note).data)
