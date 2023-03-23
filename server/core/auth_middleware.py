from .firebase import firebase_admin,auth as fire_auth
from core.models import Auth
from django.core.exceptions import ObjectDoesNotExist

class AuthMiddleware:
    
    def __init__(self,get_response) -> None:
        self.get_response = get_response
        
    def __call__(self, request) -> any:
        token:str = request.META['HTTP_AUTHORIZATION']
        token = token.replace('Bearer','').strip()
        try:
            auth_record = Auth.objects.get(pk=token)
            request.uid = auth_record.uid
        except ObjectDoesNotExist:
            decoded_token = fire_auth.verify_id_token(token)
            request.uid = decoded_token['uid']
            auth_record = Auth(
                token=token,
                uid=request.uid,
                expired_at=decoded_token['exp']
            )
            auth_record.save()
        response = self.get_response(request)
        return response