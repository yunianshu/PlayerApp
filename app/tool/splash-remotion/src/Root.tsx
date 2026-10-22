import { Composition } from 'remotion';
import { Splash } from './Splash';

export const RemotionRoot: React.FC = () => (
  <Composition
    id="Splash"
    component={Splash}
    durationInFrames={60}
    fps={30}
    width={1080}
    height={1920}
  />
);
